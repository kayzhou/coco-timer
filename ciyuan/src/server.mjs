import fs from "node:fs/promises"
import http from "node:http"
import path from "node:path"
import { pathToFileURL } from "node:url"
import { compileProject, engineStatus } from "./compile.mjs"
import { httpError } from "./errors.mjs"
import { appRoot, assertId } from "./paths.mjs"
import { createStore } from "./store.mjs"

export const LISTEN_HOST = "127.0.0.1"

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".txt": "text/plain; charset=utf-8",
  ".pdf": "application/pdf",
}

const RAW_MIME = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".pdf": "application/pdf",
  ".eps": "application/postscript",
  ".tex": "text/plain; charset=utf-8",
  ".bib": "text/plain; charset=utf-8",
  ".cls": "text/plain; charset=utf-8",
  ".sty": "text/plain; charset=utf-8",
  ".bst": "text/plain; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".md": "text/plain; charset=utf-8",
  ".csv": "text/plain; charset=utf-8",
}

function sendJson(res, status, body) {
  const payload = JSON.stringify(body)
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  })
  res.end(payload)
}

function readBody(req, limit) {
  const declared = Number(req.headers["content-length"] || 0)
  if (declared > limit) return Promise.reject(httpError(413, "文件过大"))
  return new Promise((resolve, reject) => {
    const chunks = []
    let size = 0
    req.on("data", (chunk) => {
      size += chunk.length
      if (size > limit) {
        reject(httpError(413, "文件过大"))
        req.destroy()
        return
      }
      chunks.push(chunk)
    })
    req.on("end", () => resolve(Buffer.concat(chunks)))
    req.on("error", reject)
  })
}

async function readJson(req, limit = 2_000_000) {
  const raw = await readBody(req, limit)
  try {
    return JSON.parse(raw.toString("utf8") || "{}")
  } catch {
    throw httpError(400, "请求格式不正确")
  }
}

export function createServer(options = {}) {
  const root = options.root || appRoot
  const publicDir = path.resolve(options.publicDir || path.join(root, "public"))
  const dataDir = options.dataDir || path.join(root, "data")
  const templateDir = options.templateDir || path.join(root, "templates", "article")
  const store = options.store || createStore({ dataDir, templateDir })
  const locks = new Map()

  async function compileLocked(id) {
    if (locks.has(id)) throw httpError(409, "正在编译，请稍候")
    const job = (async () => {
      const project = await store.get(id)
      const paths = store.projectPaths(id)
      const result = await compileProject({
        filesDir: paths.files,
        outputDir: paths.output,
        buildDir: paths.build,
        mainFile: project.mainFile,
      })
      const updated = await store.markCompiled(id, result.level)
      return {
        level: result.level,
        hints: result.hints,
        log: result.log,
        hasPdf: result.hasPdf,
        project: updated,
      }
    })().finally(() => locks.delete(id))
    locks.set(id, job)
    return job
  }

  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || "/", "http://127.0.0.1")
      const parts = url.pathname.split("/").filter(Boolean)
      if (parts[0] === "api") {
        await routeApi(req, res, url, parts, store, dataDir, compileLocked)
        return
      }
      await serveStatic(res, publicDir, url.pathname)
    } catch (error) {
      const status = error.status || 500
      if (status === 500) console.error(error)
      if (!res.headersSent) sendJson(res, status, { error: status === 500 ? "服务出现问题" : error.message })
      else res.destroy()
    }
  })
}

async function routeApi(req, res, url, parts, store, dataDir, compileLocked) {
  const method = req.method || "GET"
  if (method === "GET" && url.pathname === "/api/meta") {
    const engines = await engineStatus()
    sendJson(res, 200, {
      name: "词元写作台",
      language: "zh-CN",
      engine: "xelatex",
      bibliography: "gb7714-2015",
      engines,
      registration: false,
      sharing: false,
      collaboration: false,
      host: LISTEN_HOST,
      dataDir,
    })
    return
  }

  if (parts[1] !== "projects") throw httpError(404, "没有这个地址")

  if (parts.length === 2 && method === "GET") {
    sendJson(res, 200, { projects: await store.list() })
    return
  }
  if (parts.length === 2 && method === "POST") {
    const body = await readJson(req)
    sendJson(res, 201, { project: await store.create(body.name) })
    return
  }
  if (parts.length === 3 && parts[2] === "import" && method === "POST") {
    const zip = await readBody(req, 50 * 1024 * 1024)
    const temp = path.join(dataDir, `import-${Date.now()}.zip`)
    await fs.mkdir(dataDir, { recursive: true })
    await fs.writeFile(temp, zip)
    try {
      const project = await store.importZip(url.searchParams.get("name") || "", temp)
      sendJson(res, 201, { project })
    } finally {
      await fs.rm(temp, { force: true })
    }
    return
  }

  const id = assertId(parts[2] || "")
  if (parts.length === 3 && method === "GET") {
    sendJson(res, 200, { project: await store.get(id) })
    return
  }
  if (parts.length === 3 && method === "PATCH") {
    const body = await readJson(req)
    sendJson(res, 200, { project: await store.rename(id, body.name) })
    return
  }
  if (parts.length === 3 && method === "DELETE") {
    await store.remove(id)
    sendJson(res, 200, { ok: true })
    return
  }
  if (parts.length === 4 && parts[3] === "tree" && method === "GET") {
    sendJson(res, 200, { entries: await store.tree(id), project: await store.get(id) })
    return
  }
  if (parts.length === 4 && parts[3] === "file" && method === "GET") {
    sendJson(res, 200, await store.readFile(id, url.searchParams.get("path") || ""))
    return
  }
  if (parts.length === 4 && parts[3] === "file" && method === "PUT") {
    const body = await readJson(req, 2_000_000)
    if (typeof body.content !== "string" || typeof body.path !== "string") {
      throw httpError(400, "请求格式不正确")
    }
    sendJson(res, 200, await store.writeFile(id, body.path, body.content))
    return
  }
  if (parts.length === 4 && parts[3] === "file" && method === "DELETE") {
    await store.deleteFile(id, url.searchParams.get("path") || "")
    sendJson(res, 200, { ok: true })
    return
  }
  if (parts.length === 4 && parts[3] === "raw" && method === "GET") {
    const file = await store.readRaw(id, url.searchParams.get("path") || "")
    const ext = path.posix.extname(file.path).toLowerCase()
    const type = RAW_MIME[ext] || "application/octet-stream"
    res.writeHead(200, {
      "Content-Type": type,
      "Content-Length": file.data.length,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Content-Disposition": ext === ".svg" ? "attachment" : "inline",
    })
    res.end(file.data)
    return
  }
  if (parts.length === 4 && parts[3] === "upload" && method === "POST") {
    const data = await readBody(req, 20 * 1024 * 1024)
    const saved = await store.writeFile(id, url.searchParams.get("path") || "", data)
    sendJson(res, 201, saved)
    return
  }
  if (parts.length === 4 && parts[3] === "compile" && method === "POST") {
    sendJson(res, 200, await compileLocked(id))
    return
  }
  if (parts.length === 4 && parts[3] === "log" && method === "GET") {
    const logPath = path.join(store.projectPaths(id).output, "compile.log")
    const log = await fs.readFile(logPath, "utf8").catch(() => "")
    sendJson(res, 200, { log })
    return
  }
  if (parts.length === 4 && parts[3] === "pdf" && method === "GET") {
    await store.get(id)
    const pdfPath = path.join(store.projectPaths(id).output, "main.pdf")
    const data = await fs.readFile(pdfPath).catch(() => null)
    if (!data) throw httpError(404, "还没有可下载的 PDF")
    const project = await store.get(id)
    const download = url.searchParams.get("download") === "1"
    const filename = encodeURIComponent(`${project.name}.pdf`)
    res.writeHead(200, {
      "Content-Type": "application/pdf",
      "Content-Length": data.length,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Content-Disposition": download
        ? `attachment; filename="paper.pdf"; filename*=UTF-8''${filename}`
        : "inline",
    })
    res.end(data)
    return
  }
  if (parts.length === 4 && parts[3] === "export" && method === "GET") {
    const exported = await store.exportZip(id)
    const data = await fs.readFile(exported.zipPath)
    await fs.rm(exported.zipPath, { force: true })
    const filename = encodeURIComponent(`${exported.name}.zip`)
    res.writeHead(200, {
      "Content-Type": "application/zip",
      "Content-Length": data.length,
      "Cache-Control": "no-store",
      "Content-Disposition": `attachment; filename="project.zip"; filename*=UTF-8''${filename}`,
    })
    res.end(data)
    return
  }
  throw httpError(404, "没有这个地址")
}

async function serveStatic(res, publicDir, pathname) {
  const requestPath = pathname === "/" ? "/index.html" : pathname
  const decoded = decodeURIComponent(requestPath)
  const full = path.resolve(publicDir, `.${decoded}`)
  if (full !== publicDir && !full.startsWith(`${publicDir}${path.sep}`)) throw httpError(404, "没有这个文件")
  const data = await fs.readFile(full).catch(() => null)
  if (!data) throw httpError(404, "没有这个文件")
  const ext = path.extname(full).toLowerCase()
  res.writeHead(200, {
    "Content-Type": MIME[ext] || "application/octet-stream",
    "Content-Length": data.length,
    "Cache-Control": ext === ".html" ? "no-store" : "public, max-age=3600",
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy":
      "default-src 'self'; img-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; font-src 'self'; frame-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'self'",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "SAMEORIGIN",
  })
  res.end(data)
}

export function listen(server, port = 4173) {
  return new Promise((resolve, reject) => {
    server.once("error", reject)
    server.listen(port, LISTEN_HOST, () => {
      server.off("error", reject)
      resolve(server)
    })
  })
}

async function main() {
  const port = Number(process.env.PORT || 4173)
  const server = createServer()
  server.requestTimeout = 180_000
  await listen(server, port)
  console.log(`词元写作台  http://${LISTEN_HOST}:${port}`)
}

const entry = process.argv[1] ? pathToFileURL(path.resolve(process.argv[1])).href : ""
if (import.meta.url === entry) main()
