"use strict";

const DEFAULT_ADAPTER = "manual";
const DEFAULT_SOURCE = "local";

function nonnegativeInteger(value, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }

  return Math.max(0, Math.floor(number));
}

function normalizePosition(position, fallback) {
  if (!position || typeof position !== "object") {
    return fallback;
  }

  return {
    line: nonnegativeInteger(position.line, fallback.line),
    character: nonnegativeInteger(position.character, fallback.character),
  };
}

function normalizeRange(range) {
  const start = normalizePosition(range && range.start, { line: 0, character: 0 });
  const endFallback = { line: start.line, character: start.character };
  const end = normalizePosition(range && range.end, endFallback);

  if (end.line < start.line || (end.line === start.line && end.character < start.character)) {
    return { start, end: endFallback };
  }

  return { start, end };
}

function normalizeSeverity(value) {
  if (typeof value === "number" && value >= 1 && value <= 4) {
    return Math.floor(value);
  }

  switch (String(value || "").toLowerCase()) {
    case "error":
    case "e":
      return 1;
    case "warning":
    case "warn":
    case "w":
      return 2;
    case "information":
    case "info":
    case "i":
      return 3;
    case "hint":
    case "h":
      return 4;
    default:
      return 1;
  }
}

function normalizeTags(tags) {
  if (!Array.isArray(tags)) {
    return undefined;
  }

  const normalized = tags.map((tag) => Number(tag)).filter((tag) => tag === 1 || tag === 2);
  return normalized.length > 0 ? normalized : undefined;
}

function adapterKey(opts = {}) {
  const value = opts.adapter || opts.source || DEFAULT_ADAPTER;
  const key = String(value || "").trim();
  return key === "" ? DEFAULT_ADAPTER : key;
}

function diagnosticSource(item, opts, key) {
  if (item.source) {
    return item.source;
  }

  if (opts.source) {
    return opts.source;
  }

  return key === DEFAULT_ADAPTER ? DEFAULT_SOURCE : `${DEFAULT_SOURCE}:${key}`;
}

function normalizeDiagnostic(item, opts = {}, key = adapterKey(opts)) {
  if (!item || typeof item !== "object") {
    throw new Error("diagnostic items must be objects");
  }

  const message = String(item.message || "").trim();
  if (message === "") {
    throw new Error("diagnostic message must be non-empty");
  }

  const diagnostic = {
    range: normalizeRange(item.range),
    message,
    severity: normalizeSeverity(item.severity),
    source: diagnosticSource(item, opts, key),
  };

  if (item.code !== undefined && item.code !== null) {
    diagnostic.code = item.code;
  }

  const tags = normalizeTags(item.tags);
  if (tags) {
    diagnostic.tags = tags;
  }

  if (Array.isArray(item.relatedInformation)) {
    diagnostic.relatedInformation = item.relatedInformation;
  }

  if (item.codeDescription && typeof item.codeDescription === "object") {
    diagnostic.codeDescription = item.codeDescription;
  }

  return diagnostic;
}

module.exports = {
  adapterKey,
  normalizeDiagnostic,
  normalizeRange,
};
