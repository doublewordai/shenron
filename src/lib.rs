mod core;

use pyo3::exceptions::PyRuntimeError;
use pyo3::prelude::*;
use pyo3::types::PyModule;
use std::path::Path;

#[pyfunction(signature = (target, output_dir=None))]
fn generate(target: String, output_dir: Option<String>) -> PyResult<Vec<String>> {
    let files =
        core::generate_from_target(Path::new(&target), output_dir.as_deref().map(Path::new))
            .map_err(|err| PyRuntimeError::new_err(err.to_string()))?;

    Ok(files.into_iter().map(|p| p.display().to_string()).collect())
}

#[pymodule]
fn _core(_py: Python<'_>, m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(generate, m)?)?;
    Ok(())
}
