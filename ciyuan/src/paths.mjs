import path from "node:path"
import { fileURLToPath } from "node:url"
import { httpError } from "./errors.mjs"

export const appRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")

export const TEXT_EXT = new Set([".tex", ".bib", ".cls", ".sty", ".bst", ".txt", ".md", ".csv"])
export const BINARY_EXT = new Set([".png", ".jpg", ".jpeg", ".pdf", ".eps"])

const ID_RE = /^[a-f0-9]{12}$/

export function assertId(id) {
  if (!ID_RE.test(id)) throw httpError(400, "项目不存在")
  return id
}

export function extname(filePath) {
  return path.posix.extname(filePath).toLowerCase()
}

export function safeRelative(input) {
  if (typeof input !== "string" || input.includes("\0")) {
    throw httpError(400, "路径无效")
  }
  const trimmed = input.trim()
  if (!trimmed || trimmed.length > 240) throw httpError(400, "路径无效")
  const normalized = path.posix
    .normalize(trimmed.replaceAll("\\", "/"))
    .replace(/^\.\/+/, "")
    .replace(/\/+$/, "")
  if (
    !normalized ||
    normalized === "." ||
    normalized.startsWith("/") ||
    normalized.startsWith("../") ||
    normalized.includes("/../") ||
    normalized === ".."
  ) {
    throw httpError(400, "路径无效")
  }
  return normalized
}

export function cleanName(name) {
  if (typeof name !== "string") throw httpError(400, "请填写项目名称")
  const trimmed = name.trim().replace(/\s+/g, " ")
  if (!trimmed || trimmed.length > 80) throw httpError(400, "项目名称需要在 1 到 80 个字之间")
  if (/[\u0000-\u001f]/.test(trimmed)) throw httpError(400, "项目名称无效")
  return trimmed
}

export function assertAllowedFile(filePath, { binary = false } = {}) {
  const ext = extname(filePath)
  const allowed = binary ? new Set([...TEXT_EXT, ...BINARY_EXT]) : TEXT_EXT
  if (!allowed.has(ext)) throw httpError(400, "不支持这种文件类型")
  return ext
}
