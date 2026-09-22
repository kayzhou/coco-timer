import assert from "node:assert/strict"
import fs from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import test from "node:test"
import { compileLevel, explainLog } from "../src/log-hints.mjs"
import { appRoot, safeRelative } from "../src/paths.mjs"
import { LISTEN_HOST, createServer, listen } from "../src/server.mjs"

const templateDir = path.join(appRoot, "templates", "article")

function assertStatus(error, status) {
  assert.equal(error.status, status)
  return true
}

async function withServer() {
  const dataDir = await fs.mkdtemp(path.join(os.tmpdir(), "ciyuan-test-"))
  const server = createServer({ dataDir, templateDir })
  await listen(server, 0)
  const address = server.address()
  return {
    dataDir,
    base: `http://127.0.0.1:${address.port}`,
    address,
    async close() {
      await new Promise((resolve) => server.close(resolve))
      await fs.rm(dataDir, { recursive: true, force: true })
    },
  }
}

test("safeRelative rejects paths that leave the project", () => {
  assert.equal(safeRelative("chapters/intro.tex"), "chapters/intro.tex")
  assert.equal(safeRelative("foo/../main.tex"), "main.tex")
  assert.throws(() => safeRelative("../meta.json"), (error) => assertStatus(error, 400))
  assert.throws(() => safeRelative("/etc/passwd"), (error) => assertStatus(error, 400))
  assert.throws(() => safeRelative(".."), (error) => assertStatus(error, 400))
})

test("explainLog adds Chinese notes without replacing the raw log", () => {
  const log = "./main.tex:12: Undefined control sequence.\n! File `figure.png' not found.\n"
  const hints = explainLog(log)
  assert.ok(hints.some((hint) => hint.title === "命令未定义"))
  assert.ok(hints.some((hint) => hint.detail.includes("figure.png")))
  assert.equal(compileLevel({ log, hasPdf: false, failed: true }), "error")
  assert.equal(compileLevel({ log: "Output written on main.pdf", hasPdf: true, failed: false }), "success")
  assert.equal(compileLevel({ log: "LaTeX Warning: Float too large", hasPdf: true, failed: false }), "warning")
})

test("server stays on loopback and speaks Chinese", async () => {
  const ctx = await withServer()
  try {
    assert.equal(ctx.address.address, LISTEN_HOST)
    const page = await fetch(`${ctx.base}/`)
    const html = await page.text()
    assert.match(html, /词元写作台/)
    assert.match(page.headers.get("content-security-policy"), /script-src 'self'/)
    const meta = await (await fetch(`${ctx.base}/api/meta`)).json()
    assert.equal(meta.registration, false)
    assert.equal(meta.sharing, false)
    assert.equal(meta.collaboration, false)
    assert.equal(meta.language, "zh-CN")
    assert.equal(meta.engine, "xelatex")
  } finally {
    await ctx.close()
  }
})

test("project create, save, export and import", async () => {
  const ctx = await withServer()
  try {
    const created = await fetch(`${ctx.base}/api/projects`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "示例文稿" }),
    })
    assert.equal(created.status, 201)
    const project = (await created.json()).project
    const source = await (await fetch(`${ctx.base}/api/projects/${project.id}/file?path=main.tex`)).json()
    assert.match(source.content, /ctexart/)
    assert.match(source.content, /gb7714-2015/)
    assert.match(source.content, /中英文混排/)

    const saved = await fetch(`${ctx.base}/api/projects/${project.id}/file`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: "main.tex", content: `${source.content}\n% 已保存一句。\n` }),
    })
    assert.equal(saved.status, 200)
    const again = await (await fetch(`${ctx.base}/api/projects/${project.id}/file?path=main.tex`)).json()
    assert.match(again.content, /已保存一句/)

    const blocked = await fetch(`${ctx.base}/api/projects/${project.id}/file`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: "../meta.json", content: "nope" }),
    })
    assert.equal(blocked.status, 400)

    const removedMain = await fetch(`${ctx.base}/api/projects/${project.id}/file?path=main.tex`, { method: "DELETE" })
    assert.equal(removedMain.status, 400)

    const exported = await fetch(`${ctx.base}/api/projects/${project.id}/export`)
    assert.equal(exported.status, 200)
    const zip = Buffer.from(await exported.arrayBuffer())
    const imported = await fetch(`${ctx.base}/api/projects/import?name=${encodeURIComponent("导入回来")}`, {
      method: "POST",
      headers: { "Content-Type": "application/zip" },
      body: zip,
    })
    assert.equal(imported.status, 201)
    const copy = (await imported.json()).project
    const copied = await (await fetch(`${ctx.base}/api/projects/${copy.id}/file?path=main.tex`)).json()
    assert.match(copied.content, /已保存一句/)
    assert.equal(copy.name, "导入回来")
  } finally {
    await ctx.close()
  }
})

test("zip import rejects paths that escape the project", async () => {
  const ctx = await withServer()
  const marker = `ciyuan-slip-${Date.now()}.tex`
  const slipped = path.join(os.tmpdir(), marker)
  const zipPath = path.join(ctx.dataDir, "bad.zip")
  try {
    const { execFile } = await import("node:child_process")
    const script = [
      "import zipfile",
      `with zipfile.ZipFile(${JSON.stringify(zipPath)}, "w") as archive:`,
      `    archive.writestr(${JSON.stringify(`../../${marker}`)}, "escaped")`,
      `    archive.writestr("main.tex", "hello")`,
    ].join("\n")
    await new Promise((resolve, reject) => {
      execFile("python3", ["-c", script], (error) => (error ? reject(error) : resolve()))
    })
    const zip = await fs.readFile(zipPath)
    const response = await fetch(`${ctx.base}/api/projects/import?name=bad`, {
      method: "POST",
      headers: { "Content-Type": "application/zip" },
      body: zip,
    })
    assert.equal(response.status, 400)
    await assert.rejects(fs.stat(slipped))
  } finally {
    await ctx.close()
    await fs.rm(slipped, { force: true })
  }
})

test("Chinese template compiles to PDF", { timeout: 150_000 }, async (t) => {
  const { execFile } = await import("node:child_process")
  const hasEngine = await new Promise((resolve) => {
    execFile("xelatex", ["--version"], (error) => resolve(!error))
  })
  if (!hasEngine) {
    t.skip("本机没有 xelatex，跳过编译")
    return
  }
  const ctx = await withServer()
  try {
    const created = await (await fetch(`${ctx.base}/api/projects`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "编译样例" }),
    })).json()
    const response = await fetch(`${ctx.base}/api/projects/${created.project.id}/compile`, { method: "POST" })
    const result = await response.json()
    assert.equal(response.status, 200, result.error || result.log)
    if (result.level !== "success") {
      assert.fail(`${result.level}\n${result.log}`)
    }
    assert.ok(result.hasPdf)
    const pdf = await fetch(`${ctx.base}/api/projects/${created.project.id}/pdf`)
    const bytes = Buffer.from(await pdf.arrayBuffer())
    assert.equal(bytes.subarray(0, 5).toString(), "%PDF-")
  } finally {
    await ctx.close()
  }
})
