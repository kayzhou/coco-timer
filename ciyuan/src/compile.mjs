import fs from "node:fs/promises"
import path from "node:path"
import { spawn } from "node:child_process"
import { httpError } from "./errors.mjs"
import { compileLevel, explainLog } from "./log-hints.mjs"

export function runCommand(command, args, cwd, timeoutMs) {
  return new Promise((resolve) => {
    let stdout = ""
    let stderr = ""
    let settled = false
    const child = spawn(command, args, {
      cwd,
      env: { ...process.env, max_print_line: "2000" },
    })
    const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs)
    const clip = (current, chunk) => {
      const next = current + chunk.toString("utf8")
      return next.length > 400_000 ? next.slice(-320_000) : next
    }
    const finish = (result) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve(result)
    }
    child.stdout.on("data", (chunk) => {
      stdout = clip(stdout, chunk)
    })
    child.stderr.on("data", (chunk) => {
      stderr = clip(stderr, chunk)
    })
    child.on("error", (error) => {
      const missing = error.code === "ENOENT" ? `\n未找到命令 ${command}\n` : `\n${error.message}\n`
      finish({ code: 127, stdout, stderr: stderr + missing })
    })
    child.on("close", (code, signal) => {
      if (signal === "SIGKILL") stderr += `\n命令超时：${command}\n`
      finish({ code: code ?? 1, stdout, stderr })
    })
  })
}

function section(title, result) {
  return `% ${title}\n${result.stdout || ""}${result.stderr || ""}\n`
}

function lastLatexPass(log) {
  const marks = [...log.matchAll(/^% XeLaTeX .*$/gm)]
  if (marks.length === 0) return log
  return log.slice(marks[marks.length - 1].index)
}

async function exists(filePath) {
  try {
    await fs.stat(filePath)
    return true
  } catch {
    return false
  }
}

export async function engineStatus() {
  const xelatex = await runCommand("xelatex", ["--version"], process.cwd(), 8000)
  const biber = await runCommand("biber", ["--version"], process.cwd(), 8000)
  return { xelatex: xelatex.code === 0, biber: biber.code === 0 }
}

export async function compileProject({ filesDir, outputDir, buildDir, mainFile }) {
  const sourcePath = path.join(filesDir, mainFile)
  if (!(await exists(sourcePath))) throw httpError(400, "主文件不存在，无法编译")

  await fs.rm(buildDir, { recursive: true, force: true })
  await fs.mkdir(buildDir, { recursive: true })
  await fs.cp(filesDir, buildDir, { recursive: true })

  const job = mainFile.replace(/\.tex$/i, "")
  const xelatexArgs = ["-no-shell-escape", "-interaction=nonstopmode", "-file-line-error", "-synctex=1", mainFile]
  let log = ""
  let failed = false

  const first = await runCommand("xelatex", xelatexArgs, buildDir, 60_000)
  log += section("XeLaTeX 第 1 遍", first)
  if (first.code !== 0) failed = true

  const source = await fs.readFile(path.join(buildDir, mainFile), "utf8").catch(() => "")
  const auxPath = path.join(buildDir, `${job}.aux`)
  const canContinue = first.code === 0 && (await exists(auxPath))
  if (canContinue && /\\(addbibresource|printbibliography)\b/.test(source)) {
    const cited = await runCommand("biber", [job], buildDir, 40_000)
    log += section("Biber", cited)
    if (cited.code !== 0) failed = true
  } else if (canContinue && /\\bibliography\s*\{/.test(source)) {
    const cited = await runCommand("bibtex", [job], buildDir, 30_000)
    log += section("BibTeX", cited)
    if (cited.code !== 0) failed = true
  }
  if (canContinue && (/\\(addbibresource|printbibliography)\b/.test(source) || /\\bibliography\s*\{/.test(source))) {
    const second = await runCommand("xelatex", xelatexArgs, buildDir, 60_000)
    log += section("XeLaTeX 第 2 遍", second)
    if (second.code !== 0) failed = true
    const third = await runCommand("xelatex", xelatexArgs, buildDir, 60_000)
    log += section("XeLaTeX 第 3 遍", third)
    if (third.code !== 0) failed = true
  }

  await fs.mkdir(outputDir, { recursive: true })
  const produced = path.join(buildDir, `${job}.pdf`)
  const pdfPath = path.join(outputDir, "main.pdf")
  const freshPdf = await exists(produced)
  if (freshPdf) await fs.copyFile(produced, pdfPath)
  const hasPdf = freshPdf || (await exists(pdfPath))
  await fs.writeFile(path.join(outputDir, "compile.log"), log)
  const judged = lastLatexPass(log)
  const level = compileLevel({ log: judged, hasPdf: freshPdf, failed })
  return { level, hints: explainLog(judged), log, hasPdf }
}
