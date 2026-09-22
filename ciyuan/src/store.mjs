import crypto from "node:crypto"
import fs from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { spawn } from "node:child_process"
import { httpError } from "./errors.mjs"
import { appRoot, assertAllowedFile, assertId, extname, safeRelative, TEXT_EXT, cleanName } from "./paths.mjs"

const zipTool = path.join(appRoot, "scripts", "zip_tool.py")

function runZip(args) {
  return new Promise((resolve, reject) => {
    const child = spawn("python3", [zipTool, ...args])
    let stderr = ""
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8")
    })
    child.on("error", (error) => reject(httpError(500, error.message)))
    child.on("close", (code) => {
      if (code === 0) resolve()
      else reject(httpError(400, stderr.trim() || "压缩包无法处理"))
    })
  })
}

async function exists(filePath) {
  try {
    await fs.stat(filePath)
    return true
  } catch {
    return false
  }
}

export function createStore({ dataDir, templateDir }) {
  const projectsDir = path.join(dataDir, "projects")

  async function ensure() {
    await fs.mkdir(projectsDir, { recursive: true })
  }

  function projectDir(id) {
    assertId(id)
    const resolved = path.resolve(projectsDir, id)
    if (path.dirname(resolved) !== path.resolve(projectsDir)) throw httpError(400, "项目不存在")
    return resolved
  }

  function filesDir(id) {
    return path.join(projectDir(id), "files")
  }

  function resolveInside(id, relativePath) {
    const root = path.resolve(filesDir(id))
    const full = path.resolve(root, relativePath)
    if (full !== root && !full.startsWith(`${root}${path.sep}`)) throw httpError(400, "路径无效")
    return full
  }

  async function readMeta(id) {
    try {
      const raw = await fs.readFile(path.join(projectDir(id), "meta.json"), "utf8")
      const meta = JSON.parse(raw)
      if (meta.id !== id) throw new Error("id mismatch")
      return meta
    } catch (error) {
      if (error.status) throw error
      throw httpError(404, "找不到这个项目")
    }
  }

  async function writeMeta(meta) {
    await fs.writeFile(path.join(projectDir(meta.id), "meta.json"), `${JSON.stringify(meta, null, 2)}\n`)
  }

  async function present(meta) {
    return { ...meta, hasPdf: await exists(path.join(projectDir(meta.id), "output", "main.pdf")) }
  }

  async function walkTex(dir, prefix = "") {
    const found = []
    const entries = await fs.readdir(dir, { withFileTypes: true })
    for (const entry of entries) {
      const rel = prefix ? `${prefix}/${entry.name}` : entry.name
      if (entry.isDirectory()) found.push(...(await walkTex(path.join(dir, entry.name), rel)))
      else if (entry.isFile() && extname(entry.name) === ".tex") found.push(rel)
    }
    return found
  }

  return {
    async list() {
      await ensure()
      const names = await fs.readdir(projectsDir)
      const projects = []
      for (const id of names) {
        if (!/^[a-f0-9]{12}$/.test(id)) continue
        try {
          projects.push(await present(await readMeta(id)))
        } catch {
          // Skip a half-written project directory.
        }
      }
      projects.sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)))
      return projects
    },

    async get(id) {
      await ensure()
      return present(await readMeta(id))
    },

    async create(name) {
      await ensure()
      const id = crypto.randomBytes(6).toString("hex")
      const now = new Date().toISOString()
      const root = projectDir(id)
      await fs.mkdir(path.join(root, "output"), { recursive: true })
      await fs.cp(templateDir, path.join(root, "files"), { recursive: true })
      const meta = {
        id,
        name: cleanName(name),
        createdAt: now,
        updatedAt: now,
        mainFile: "main.tex",
        lastCompile: null,
      }
      await writeMeta(meta)
      return present(meta)
    },

    async rename(id, name) {
      const meta = await readMeta(id)
      meta.name = cleanName(name)
      meta.updatedAt = new Date().toISOString()
      await writeMeta(meta)
      return present(meta)
    },

    async remove(id) {
      const root = projectDir(id)
      if (!(await exists(path.join(root, "meta.json")))) throw httpError(404, "找不到这个项目")
      await fs.rm(root, { recursive: true, force: true })
    },

    async tree(id) {
      await readMeta(id)
      const root = filesDir(id)
      const entries = []
      async function walk(dir, prefix) {
        const items = await fs.readdir(dir, { withFileTypes: true })
        for (const item of items) {
          const rel = prefix ? `${prefix}/${item.name}` : item.name
          if (item.isDirectory()) await walk(path.join(dir, item.name), rel)
          else if (item.isFile()) {
            const stat = await fs.stat(path.join(dir, item.name))
            entries.push({ path: rel, size: stat.size, ext: extname(item.name) })
          }
        }
      }
      if (await exists(root)) await walk(root, "")
      entries.sort((a, b) => a.path.localeCompare(b.path, "zh"))
      return entries
    },

    async readFile(id, relativePath) {
      await readMeta(id)
      const safe = safeRelative(relativePath)
      const full = resolveInside(id, safe)
      let stat
      try {
        stat = await fs.stat(full)
      } catch {
        throw httpError(404, "找不到这个文件")
      }
      if (!stat.isFile()) throw httpError(400, "路径无效")
      if (!TEXT_EXT.has(extname(safe))) return { path: safe, binary: true, size: stat.size }
      return { path: safe, binary: false, size: stat.size, content: await fs.readFile(full, "utf8") }
    },

    async readRaw(id, relativePath) {
      await readMeta(id)
      const safe = safeRelative(relativePath)
      assertAllowedFile(safe, { binary: true })
      const full = resolveInside(id, safe)
      try {
        const data = await fs.readFile(full)
        return { path: safe, data }
      } catch {
        throw httpError(404, "找不到这个文件")
      }
    },

    async writeFile(id, relativePath, data) {
      const meta = await readMeta(id)
      const safe = safeRelative(relativePath)
      const buffer = Buffer.isBuffer(data) ? data : Buffer.from(String(data), "utf8")
      if (buffer.length > 20 * 1024 * 1024) throw httpError(413, "文件过大")
      assertAllowedFile(safe, { binary: Buffer.isBuffer(data) })
      if (!Buffer.isBuffer(data)) assertAllowedFile(safe, { binary: false })
      const full = resolveInside(id, safe)
      await fs.mkdir(path.dirname(full), { recursive: true })
      await fs.writeFile(full, buffer)
      meta.updatedAt = new Date().toISOString()
      await writeMeta(meta)
      return { path: safe, size: buffer.length }
    },

    async deleteFile(id, relativePath) {
      const meta = await readMeta(id)
      const safe = safeRelative(relativePath)
      if (safe === meta.mainFile) throw httpError(400, "主文件不能删除")
      const full = resolveInside(id, safe)
      try {
        await fs.rm(full)
      } catch {
        throw httpError(404, "找不到这个文件")
      }
      meta.updatedAt = new Date().toISOString()
      await writeMeta(meta)
    },

    async markCompiled(id, level) {
      const meta = await readMeta(id)
      meta.lastCompile = { level, at: new Date().toISOString() }
      meta.updatedAt = new Date().toISOString()
      await writeMeta(meta)
      return present(meta)
    },

    projectPaths(id) {
      const root = projectDir(id)
      return {
        root,
        files: path.join(root, "files"),
        output: path.join(root, "output"),
        build: path.join(root, "build"),
      }
    },

    async exportZip(id) {
      const meta = await readMeta(id)
      const dest = path.join(os.tmpdir(), `ciyuan-${id}-${crypto.randomBytes(4).toString("hex")}.zip`)
      await runZip(["pack", filesDir(id), dest])
      return { zipPath: dest, name: meta.name }
    },

    async importZip(name, zipPath) {
      await ensure()
      const temp = await fs.mkdtemp(path.join(os.tmpdir(), "ciyuan-import-"))
      try {
        const extracted = path.join(temp, "files")
        await runZip(["unpack", zipPath, extracted])
        const texFiles = await walkTex(extracted)
        if (texFiles.length === 0) throw httpError(400, "压缩包里没有 .tex 文件")
        const id = crypto.randomBytes(6).toString("hex")
        const root = projectDir(id)
        await fs.mkdir(path.join(root, "output"), { recursive: true })
        await fs.cp(extracted, path.join(root, "files"), { recursive: true })
        const now = new Date().toISOString()
        const meta = {
          id,
          name: cleanName(name || "导入的项目"),
          createdAt: now,
          updatedAt: now,
          mainFile: texFiles.includes("main.tex") ? "main.tex" : texFiles.sort((a, b) => a.localeCompare(b, "zh"))[0],
          lastCompile: null,
        }
        await writeMeta(meta)
        return present(meta)
      } finally {
        await fs.rm(temp, { recursive: true, force: true })
      }
    },
  }
}
