"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_VENV_NAMES = [".venv", "venv", "env", ".env"];
const MANAGER_TIMEOUT_MS = 2500;

function stringValue(value) {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

function pythonExecutableForEnv(envDir) {
  const candidates = process.platform === "win32"
    ? [path.join(envDir, "Scripts", "python.exe"), path.join(envDir, "python.exe")]
    : [path.join(envDir, "bin", "python"), path.join(envDir, "bin", "python3")];

  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function environmentFromDir(envDir, source) {
  if (!envDir) {
    return null;
  }

  const resolved = path.resolve(envDir);
  const pythonPath = pythonExecutableForEnv(resolved);
  if (!pythonPath) {
    return null;
  }

  return {
    envDir: resolved,
    pythonPath,
    source,
    venv: path.basename(resolved),
    venvPath: path.dirname(resolved),
  };
}

function environmentFromPythonPath(pythonPath, source) {
  const configured = stringValue(pythonPath);
  if (!configured) {
    return null;
  }

  const resolved = path.resolve(configured);
  const parent = path.basename(path.dirname(resolved)).toLowerCase();
  const envDir = parent === "bin" || parent === "scripts" ? path.dirname(path.dirname(resolved)) : null;
  const info = {
    pythonPath: resolved,
    source,
  };

  if (envDir) {
    info.envDir = envDir;
    info.venv = path.basename(envDir);
    info.venvPath = path.dirname(envDir);
  }

  return info;
}

function configuredPythonPath(workspace, opts, configValue) {
  const explicit = stringValue(opts && opts.pythonPath)
    || stringValue(configValue(workspace, "localDiagnostics", "pyright.pythonPath", ""))
    || stringValue(process.env.LOCAL_DIAGNOSTICS_PYTHON);

  return explicit ? environmentFromPythonPath(explicit, "configured") : null;
}

function venvDiscoveryEnabled(workspace, opts, configValue) {
  if (opts && Object.prototype.hasOwnProperty.call(opts, "discoverVenv")) {
    return opts.discoverVenv !== false;
  }

  return configValue(workspace, "localDiagnostics", "pyright.discoverVenv", true) !== false;
}

function configuredVenvNames(workspace, opts, configValue) {
  const value = opts && Array.isArray(opts.venvNames)
    ? opts.venvNames
    : configValue(workspace, "localDiagnostics", "pyright.venvNames", DEFAULT_VENV_NAMES);

  if (!Array.isArray(value)) {
    return DEFAULT_VENV_NAMES;
  }

  const names = value.map(stringValue).filter(Boolean);
  return names.length > 0 ? Array.from(new Set(names)) : DEFAULT_VENV_NAMES;
}

function runCommand(command, args, cwd) {
  try {
    const result = childProcess.spawnSync(command, args, {
      cwd,
      encoding: "utf8",
      timeout: MANAGER_TIMEOUT_MS,
      windowsHide: true,
    });

    return result.status === 0 && result.stdout ? result.stdout.trim() : "";
  } catch (_error) {
    return "";
  }
}

function addSearchDir(searchDirs, dir) {
  if (!dir) {
    return;
  }

  try {
    searchDirs.add(path.resolve(dir));
  } catch (_error) {
  }
}

function collectSearchDirs(root, targetFiles) {
  const searchDirs = new Set();
  const home = process.env.HOME ? path.resolve(process.env.HOME) : null;

  for (const target of targetFiles || []) {
    let dir = target && fs.existsSync(target) && fs.statSync(target).isDirectory() ? target : path.dirname(target || "");
    let previous = null;

    while (dir && dir !== previous) {
      addSearchDir(searchDirs, dir);
      if (home && path.resolve(dir) === home) {
        break;
      }
      previous = dir;
      dir = path.dirname(dir);
    }
  }

  addSearchDir(searchDirs, root);
  return Array.from(searchDirs);
}

function discoverNamedVenv(searchDirs, venvNames) {
  for (const dir of searchDirs) {
    for (const name of venvNames) {
      const info = environmentFromDir(path.join(dir, name), `venv:${name}`);
      if (info) {
        return info;
      }
    }
  }

  return null;
}

function discoverManagedVenv(searchDirs) {
  for (const dir of searchDirs) {
    if (fs.existsSync(path.join(dir, "Pipfile"))) {
      const pythonPath = runCommand("pipenv", ["--py"], dir);
      const info = environmentFromPythonPath(pythonPath, "pipenv");
      if (info) {
        return info;
      }
    }

    if (fs.existsSync(path.join(dir, "poetry.lock"))) {
      const output = runCommand("poetry", ["env", "list", "--full-path", "--no-ansi"], dir);
      const lines = output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
      const active = lines.find((line) => line.includes("(Activated)")) || lines[lines.length - 1];
      const envDir = active ? active.replace(/\s*\(Activated\)\s*/, "").trim() : "";
      const info = environmentFromDir(envDir, "poetry");
      if (info) {
        return info;
      }
    }

    if (fs.existsSync(path.join(dir, ".pdm-python"))) {
      const pythonPath = runCommand("pdm", ["info", "--python"], dir);
      const info = environmentFromPythonPath(pythonPath, "pdm");
      if (info) {
        return info;
      }
    }
  }

  return null;
}

function discoverAnyChildVenv(searchDirs) {
  for (const dir of searchDirs) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (_error) {
      continue;
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }

      const envDir = path.join(dir, entry.name);
      if (!fs.existsSync(path.join(envDir, "pyvenv.cfg"))) {
        continue;
      }

      const info = environmentFromDir(envDir, "pyvenv.cfg");
      if (info) {
        return info;
      }
    }
  }

  return null;
}

function discoverFromEnvironment() {
  const virtualEnv = environmentFromDir(process.env.VIRTUAL_ENV, "VIRTUAL_ENV");
  if (virtualEnv) {
    return virtualEnv;
  }

  return environmentFromDir(process.env.CONDA_PREFIX, "CONDA_PREFIX");
}

function resolvePythonEnvironment({ root, targetFiles, workspace, opts = {}, configValue }) {
  const explicit = configuredPythonPath(workspace, opts, configValue);
  if (explicit) {
    return explicit;
  }

  if (!venvDiscoveryEnabled(workspace, opts, configValue)) {
    return null;
  }

  const fromEnvironment = discoverFromEnvironment();
  if (fromEnvironment) {
    return fromEnvironment;
  }

  const searchDirs = collectSearchDirs(root, targetFiles);
  const venvNames = configuredVenvNames(workspace, opts, configValue);

  return discoverNamedVenv(searchDirs, venvNames)
    || discoverManagedVenv(searchDirs)
    || discoverAnyChildVenv(searchDirs);
}

function createPythonProcessEnv(baseEnv, environment) {
  if (!environment || !environment.envDir) {
    return baseEnv;
  }

  const binDir = path.dirname(environment.pythonPath);
  const separator = process.platform === "win32" ? ";" : ":";
  const env = Object.assign({}, baseEnv);
  env.PATH = `${binDir}${separator}${baseEnv.PATH || ""}`;

  if (fs.existsSync(path.join(environment.envDir, "pyvenv.cfg"))) {
    env.VIRTUAL_ENV = environment.envDir;
  }

  return env;
}

module.exports = {
  DEFAULT_VENV_NAMES,
  createPythonProcessEnv,
  resolvePythonEnvironment,
};
