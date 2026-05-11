"use strict";

const path = require("node:path");

function createUriTools(Uri) {
  function normalizeUri(input) {
    if (typeof input !== "string" || input.trim() === "") {
      throw new Error("uri must be a non-empty string");
    }

    const value = input.trim();
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) {
      return Uri.parse(value).toString();
    }

    return Uri.file(value).toString();
  }

  function uriToFile(uri) {
    try {
      const parsed = Uri.parse(uri);
      if (parsed.scheme !== "file") {
        return null;
      }
      return parsed.fsPath;
    } catch (_error) {
      return null;
    }
  }

  function fileToUri(file) {
    return Uri.file(path.resolve(file)).toString();
  }

  function normalizePathForLookup(file) {
    const normalized = path.resolve(file);
    return process.platform === "win32" ? normalized.toLowerCase() : normalized;
  }

  return {
    fileToUri,
    normalizePathForLookup,
    normalizeUri,
    uriToFile,
  };
}

module.exports = {
  createUriTools,
};
