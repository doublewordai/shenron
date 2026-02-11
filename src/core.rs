use serde::{Deserialize, Serialize};
use serde_json::json;
use std::ffi::OsStr;
use std::fmt::Write as _;
use std::fs;
use std::io::Write as _;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use tempfile::NamedTempFile;
use thiserror::Error;

const GENERATED_DIR: &str = ".generated";

#[derive(Debug, Error)]
pub enum ShenronError {
    #[error("target path does not exist: {0}")]
    MissingTarget(PathBuf),
    #[error("no config file (*.yml or *.yaml) found in {0}")]
    MissingConfig(PathBuf),
    #[error("multiple config files found in {dir}: {files}")]
    AmbiguousConfig { dir: PathBuf, files: String },
    #[error("failed to read {path}: {source}")]
    ReadFile {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to parse YAML config {path}: {source}")]
    ParseConfig {
        path: PathBuf,
        source: serde_yaml::Error,
    },
    #[error("config validation failed: {0}")]
    Validation(String),
    #[error("failed to write {path}: {source}")]
    WriteFile {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to serialize JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("argument contains unsupported null byte: {0}")]
    Quote(String),
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct ShenronConfig {
    pub model_name: String,
    pub cuda_version: u16,
    pub tensor_parallel_size: u16,
    pub shenron_version: String,
    pub onwards_version: String,

    pub api_key: String,
    pub vllm_flashinfer_moe_backend: String,
    pub vllm_port: u16,
    pub vllm_host: String,
    pub onwards_port: u16,

    pub prometheus_port: u16,
    pub prometheus_version: String,

    pub scouter_version: String,
    pub scouter_collector_instance: String,
    pub scouter_collector_url: Option<String>,
    pub scouter_reporter_interval: u32,
    pub scouter_ingest_api_key: String,

    pub gpu_memory_utilization: f32,
    pub limit_mm_per_prompt_video: u32,
    pub scheduling_policy: String,
    pub tool_call_parser: String,
    pub generation_config: String,
    pub override_generation_config: serde_json::Value,
    pub trust_remote_code: bool,
    pub async_scheduling: bool,
    pub enable_auto_tool_choice: bool,
}

impl Default for ShenronConfig {
    fn default() -> Self {
        Self {
            model_name: "Qwen/Qwen3-0.6B".to_string(),
            cuda_version: 126,
            tensor_parallel_size: 1,
            shenron_version: "latest".to_string(),
            onwards_version: "latest".to_string(),
            api_key: "sk-".to_string(),
            vllm_flashinfer_moe_backend: "throughput".to_string(),
            vllm_port: 8000,
            vllm_host: "0.0.0.0".to_string(),
            onwards_port: 3000,
            prometheus_port: 9090,
            prometheus_version: "v2.51.2".to_string(),
            scouter_version: "latest".to_string(),
            scouter_collector_instance: "host.docker.internal".to_string(),
            scouter_collector_url: None,
            scouter_reporter_interval: 10,
            scouter_ingest_api_key: "api-key".to_string(),
            gpu_memory_utilization: 0.7,
            limit_mm_per_prompt_video: 0,
            scheduling_policy: "priority".to_string(),
            tool_call_parser: "hermes".to_string(),
            generation_config: "auto".to_string(),
            override_generation_config: json!({
                "max_new_tokens": 16384,
                "presence_penalty": 1.5,
                "temperature": 0.7,
                "top_p": 0.8,
                "top_k": 20,
                "min_p": 0,
            }),
            trust_remote_code: true,
            async_scheduling: true,
            enable_auto_tool_choice: true,
        }
    }
}

impl ShenronConfig {
    fn validate(&self) -> Result<(), ShenronError> {
        if self.model_name.trim().is_empty() {
            return Err(ShenronError::Validation(
                "model_name must be set".to_string(),
            ));
        }
        if self.shenron_version.trim().is_empty() {
            return Err(ShenronError::Validation(
                "shenron_version must be set".to_string(),
            ));
        }
        if self.tensor_parallel_size == 0 {
            return Err(ShenronError::Validation(
                "tensor_parallel_size must be greater than 0".to_string(),
            ));
        }
        if !(0.0..=1.0).contains(&self.gpu_memory_utilization) {
            return Err(ShenronError::Validation(
                "gpu_memory_utilization must be between 0 and 1".to_string(),
            ));
        }
        Ok(())
    }

    fn scouter_collector_url(&self) -> String {
        self.scouter_collector_url
            .clone()
            .unwrap_or_else(|| format!("http://{}:4321", self.scouter_collector_instance))
    }
}

pub fn generate_from_target(
    target: &Path,
    output_dir: Option<&Path>,
) -> Result<Vec<PathBuf>, ShenronError> {
    let config_path = resolve_config_path(target)?;
    let config = load_config(&config_path)?;

    let out_dir = output_dir
        .map(Path::to_path_buf)
        .unwrap_or_else(|| default_output_dir(target, &config_path));

    generate(&config, &out_dir)
}

fn default_output_dir(target: &Path, config_path: &Path) -> PathBuf {
    if target.is_dir() {
        target.to_path_buf()
    } else {
        config_path
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| PathBuf::from("."))
    }
}

pub fn resolve_config_path(target: &Path) -> Result<PathBuf, ShenronError> {
    if !target.exists() {
        return Err(ShenronError::MissingTarget(target.to_path_buf()));
    }

    if target.is_file() {
        return Ok(target.to_path_buf());
    }

    let mut configs = fs::read_dir(target)
        .map_err(|source| ShenronError::ReadFile {
            path: target.to_path_buf(),
            source,
        })?
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.is_file())
        .filter(|p| is_config_candidate(p))
        .collect::<Vec<_>>();

    configs.sort();

    if configs.is_empty() {
        return Err(ShenronError::MissingConfig(target.to_path_buf()));
    }

    if configs.len() == 1 {
        return Ok(configs.remove(0));
    }

    for default_name in ["shenron.yml", "shenron.yaml"] {
        let candidate = target.join(default_name);
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    let files = configs
        .iter()
        .filter_map(|p| p.file_name().and_then(OsStr::to_str))
        .collect::<Vec<_>>()
        .join(", ");

    Err(ShenronError::AmbiguousConfig {
        dir: target.to_path_buf(),
        files,
    })
}

fn is_config_candidate(path: &Path) -> bool {
    let is_yaml = path
        .extension()
        .and_then(OsStr::to_str)
        .map(|ext| matches!(ext, "yml" | "yaml"))
        .unwrap_or(false);
    if !is_yaml {
        return false;
    }

    let name = path.file_name().and_then(OsStr::to_str).unwrap_or_default();
    !matches!(name, "docker-compose.yml" | "docker-compose.yaml")
}

pub fn load_config(path: &Path) -> Result<ShenronConfig, ShenronError> {
    let raw = fs::read_to_string(path).map_err(|source| ShenronError::ReadFile {
        path: path.to_path_buf(),
        source,
    })?;

    let config = serde_yaml::from_str::<ShenronConfig>(&raw).map_err(|source| {
        ShenronError::ParseConfig {
            path: path.to_path_buf(),
            source,
        }
    })?;

    config.validate()?;
    Ok(config)
}

pub fn generate(config: &ShenronConfig, output_dir: &Path) -> Result<Vec<PathBuf>, ShenronError> {
    fs::create_dir_all(output_dir).map_err(|source| ShenronError::WriteFile {
        path: output_dir.to_path_buf(),
        source,
    })?;

    let generated_dir = output_dir.join(GENERATED_DIR);
    fs::create_dir_all(&generated_dir).map_err(|source| ShenronError::WriteFile {
        path: generated_dir.clone(),
        source,
    })?;

    let onwards_config_path = generated_dir.join("onwards_config.json");
    let prometheus_path = generated_dir.join("prometheus.yml");
    let scouter_env_path = generated_dir.join("scouter_reporter.env");
    let vllm_start_path = generated_dir.join("vllm_start.sh");
    let compose_path = output_dir.join("docker-compose.yml");

    write_atomic(
        &onwards_config_path,
        render_onwards_config(config)?.as_bytes(),
        false,
    )?;
    write_atomic(
        &prometheus_path,
        render_prometheus_config(config).as_bytes(),
        false,
    )?;
    write_atomic(
        &scouter_env_path,
        render_scouter_reporter_env(config).as_bytes(),
        false,
    )?;
    write_atomic(
        &vllm_start_path,
        render_vllm_start(config)?.as_bytes(),
        true,
    )?;
    write_atomic(&compose_path, render_compose(config).as_bytes(), false)?;

    Ok(vec![
        compose_path,
        onwards_config_path,
        prometheus_path,
        scouter_env_path,
        vllm_start_path,
    ])
}

fn write_atomic(path: &Path, content: &[u8], executable: bool) -> Result<(), ShenronError> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));

    let mut tmp = NamedTempFile::new_in(parent).map_err(|source| ShenronError::WriteFile {
        path: path.to_path_buf(),
        source,
    })?;

    tmp.write_all(content)
        .map_err(|source| ShenronError::WriteFile {
            path: path.to_path_buf(),
            source,
        })?;

    if executable {
        #[cfg(unix)]
        {
            let mut perms = tmp
                .as_file()
                .metadata()
                .map_err(|source| ShenronError::WriteFile {
                    path: path.to_path_buf(),
                    source,
                })?
                .permissions();
            perms.set_mode(0o755);
            tmp.as_file()
                .set_permissions(perms)
                .map_err(|source| ShenronError::WriteFile {
                    path: path.to_path_buf(),
                    source,
                })?;
        }
    }

    tmp.persist(path)
        .map_err(|persist| ShenronError::WriteFile {
            path: path.to_path_buf(),
            source: persist.error,
        })?;

    Ok(())
}

fn render_onwards_config(config: &ShenronConfig) -> Result<String, ShenronError> {
    let value = json!({
      "targets": {
        config.model_name.clone(): {
          "url": format!("http://vllm:{}/v1", config.vllm_port),
          "keys": [config.api_key],
          "onwards_model": config.model_name
        }
      }
    });

    Ok(serde_json::to_string_pretty(&value)?)
}

fn render_prometheus_config(config: &ShenronConfig) -> String {
    format!(
        "global:\n  scrape_interval: 15s\n\nscrape_configs:\n  - job_name: vllm\n    metrics_path: /metrics\n    static_configs:\n      - targets: [\"vllm:{}\"]\n",
        config.vllm_port
    )
}

fn render_scouter_reporter_env(config: &ShenronConfig) -> String {
    format!(
        "SCOUTER_MODE=reporter\nPROMETHEUS_URL=http://prometheus:9090\nCOLLECTOR_URL={}\nREPORTER_INTERVAL={}\nMODEL_NAME={}\nSCOUTER_INGEST_API_KEY={}\n",
        config.scouter_collector_url(),
        config.scouter_reporter_interval,
        config.model_name,
        config.scouter_ingest_api_key
    )
}

fn render_vllm_start(config: &ShenronConfig) -> Result<String, ShenronError> {
    let override_json = serde_json::to_string(&config.override_generation_config)?;

    let mut args = vec![
        "--model".to_string(),
        config.model_name.clone(),
        "--port".to_string(),
        config.vllm_port.to_string(),
        "--host".to_string(),
        config.vllm_host.clone(),
        "--gpu-memory-utilization".to_string(),
        config.gpu_memory_utilization.to_string(),
        "--tensor-parallel-size".to_string(),
        config.tensor_parallel_size.to_string(),
        "--limit-mm-per-prompt.video".to_string(),
        config.limit_mm_per_prompt_video.to_string(),
        "--scheduling-policy".to_string(),
        config.scheduling_policy.clone(),
        "--tool-call-parser".to_string(),
        config.tool_call_parser.clone(),
        "--generation-config".to_string(),
        config.generation_config.clone(),
        "--override-generation-config".to_string(),
        override_json,
    ];

    if config.trust_remote_code {
        args.push("--trust-remote-code".to_string());
    }
    if config.async_scheduling {
        args.push("--async-scheduling".to_string());
    }
    if config.enable_auto_tool_choice {
        args.push("--enable-auto-tool-choice".to_string());
    }

    let joined = args
        .iter()
        .map(|a| quote_arg(a))
        .collect::<Result<Vec<_>, _>>()?
        .join(" ");

    let backend = quote_arg(&config.vllm_flashinfer_moe_backend)?;

    Ok(format!(
        "#!/usr/bin/env bash\nset -euo pipefail\n\nexport VLLM_FLASHINFER_MOE_BACKEND={}\nexec vllm serve {}\n",
        backend,
        joined
    ))
}

fn quote_arg(value: &str) -> Result<String, ShenronError> {
    shlex::try_quote(value)
        .map(|quoted| quoted.to_string())
        .map_err(|_| ShenronError::Quote(value.to_string()))
}

fn render_compose(config: &ShenronConfig) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "name: shenron-cu{}", config.cuda_version);
    let _ = writeln!(out);
    let _ = writeln!(out, "services:");
    let _ = writeln!(out, "  vllm:");
    let _ = writeln!(
        out,
        "    image: ghcr.io/doublewordai/shenron:{}-cu{}",
        config.shenron_version, config.cuda_version
    );
    let _ = writeln!(out, "    restart: unless-stopped");
    let _ = writeln!(out, "    ulimits:");
    let _ = writeln!(out, "      nofile:");
    let _ = writeln!(out, "        soft: 65535");
    let _ = writeln!(out, "        hard: 524288");
    let _ = writeln!(
        out,
        "    command: [\"bash\",\"-lc\",\"source /opt/shenron/.venv/bin/activate && exec bash /generated/vllm_start.sh\"]"
    );
    let _ = writeln!(out, "    volumes:");
    let _ = writeln!(
        out,
        "      - $HOME/.cache/huggingface:/root/.cache/huggingface"
    );
    let _ = writeln!(out, "      - ./.generated:/generated:ro");
    let _ = writeln!(out, "    deploy:");
    let _ = writeln!(out, "      resources:");
    let _ = writeln!(out, "        reservations:");
    let _ = writeln!(out, "          devices:");
    let _ = writeln!(out, "            - capabilities: [gpu]");
    let _ = writeln!(out);

    let _ = writeln!(out, "  onwards:");
    let _ = writeln!(
        out,
        "    image: ghcr.io/doublewordai/onwards:{}",
        config.onwards_version
    );
    let _ = writeln!(out, "    depends_on:");
    let _ = writeln!(out, "      - vllm");
    let _ = writeln!(
        out,
        "    command: [\"--targets\",\"/generated/onwards_config.json\",\"--port\",\"{}\"]",
        config.onwards_port
    );
    let _ = writeln!(out, "    volumes:");
    let _ = writeln!(out, "      - ./.generated:/generated:ro");
    let _ = writeln!(out, "    ports:");
    let _ = writeln!(
        out,
        "      - \"{}:{}\"",
        config.onwards_port, config.onwards_port
    );
    let _ = writeln!(out);

    let _ = writeln!(out, "  prometheus:");
    let _ = writeln!(
        out,
        "    image: prom/prometheus:{}",
        config.prometheus_version
    );
    let _ = writeln!(out, "    depends_on:");
    let _ = writeln!(out, "      - vllm");
    let _ = writeln!(out, "    volumes:");
    let _ = writeln!(
        out,
        "      - ./.generated/prometheus.yml:/etc/prometheus/prometheus.yml:ro"
    );
    let _ = writeln!(out, "    ports:");
    let _ = writeln!(
        out,
        "      - \"{}:{}\"",
        config.prometheus_port, config.prometheus_port
    );
    let _ = writeln!(out);

    let _ = writeln!(out, "  scouter-reporter:");
    let _ = writeln!(
        out,
        "    image: ghcr.io/doublewordai/scouter:{}",
        config.scouter_version
    );
    let _ = writeln!(out, "    restart: unless-stopped");
    let _ = writeln!(out, "    depends_on:");
    let _ = writeln!(out, "      - prometheus");
    let _ = writeln!(out, "    env_file:");
    let _ = writeln!(out, "      - ./.generated/scouter_reporter.env");
    let _ = writeln!(out, "    extra_hosts:");
    let _ = writeln!(out, "      - \"host.docker.internal:host-gateway\"");

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn resolves_single_config_file_from_directory() {
        let dir = tempdir().expect("tempdir");
        let cfg = dir.path().join("Qwen06B-cu126-TP1.yml");
        fs::write(&cfg, "model_name: Qwen/Qwen3-0.6B\n").expect("write config");

        let resolved = resolve_config_path(dir.path()).expect("resolve");
        assert_eq!(resolved, cfg);
    }

    #[test]
    fn generates_expected_files() {
        let dir = tempdir().expect("tempdir");
        let output = generate(&ShenronConfig::default(), dir.path()).expect("generate");

        assert_eq!(output.len(), 5);
        assert!(dir.path().join("docker-compose.yml").exists());
        assert!(dir.path().join(".generated/onwards_config.json").exists());
        assert!(dir.path().join(".generated/prometheus.yml").exists());
        assert!(dir.path().join(".generated/scouter_reporter.env").exists());
        assert!(dir.path().join(".generated/vllm_start.sh").exists());
    }

    #[test]
    fn directory_resolution_ignores_generated_compose_file() {
        let dir = tempdir().expect("tempdir");
        let cfg = dir.path().join("Qwen06B-cu126-TP1.yml");
        fs::write(&cfg, "model_name: Qwen/Qwen3-0.6B\n").expect("write config");
        fs::write(dir.path().join("docker-compose.yml"), "name: test\n").expect("write compose");

        let resolved = resolve_config_path(dir.path()).expect("resolve");
        assert_eq!(resolved, cfg);
    }

    #[test]
    fn compose_contains_concrete_image_tags() {
        let config = ShenronConfig::default();
        let compose = render_compose(&config);
        assert!(compose.contains("ghcr.io/doublewordai/shenron:latest-cu126"));
        assert!(compose.contains("ghcr.io/doublewordai/onwards:latest"));
        assert!(!compose.contains("${SHENRON_VERSION}"));
    }
}
