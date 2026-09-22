const app = document.querySelector("#app")
const toastNode = document.querySelector("#toast")
let session = null
let toastTimer = 0

function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs)) {
    if (value == null || value === false) continue
    if (key === "class") node.className = value
    else if (key === "text") node.textContent = value
    else if (key.startsWith("on") && typeof value === "function") node.addEventListener(key.slice(2).toLowerCase(), value)
    else node.setAttribute(key, String(value))
  }
  for (const child of [].concat(children)) if (child != null) node.append(child)
  return node
}

function toast(message) {
  toastNode.textContent = message
  toastNode.hidden = false
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => {
    toastNode.hidden = true
  }, 4200)
}

async function api(path, options = {}) {
  const headers = { ...options.headers }
  if (typeof options.body === "string" && !headers["Content-Type"]) headers["Content-Type"] = "application/json"
  const response = await fetch(path, { ...options, headers })
  const type = response.headers.get("content-type") || ""
  const data = type.includes("json") ? await response.json() : await response.text()
  if (!response.ok) {
    const error = new Error(data && data.error ? data.error : "请求没有完成")
    error.status = response.status
    throw error
  }
  return data
}

function formatTime(iso) {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return ""
  const hours = String(date.getHours()).padStart(2, "0")
  const minutes = String(date.getMinutes()).padStart(2, "0")
  return `${date.getMonth() + 1}月${date.getDate()}日 ${hours}:${minutes}`
}

function formatSize(size) {
  if (size < 1024) return `${size} B`
  if (size < 1024 * 1024) return `${Math.round(size / 1024)} KB`
  return `${(size / 1024 / 1024).toFixed(1)} MB`
}

function brand() {
  return el("a", { class: "brand", href: "#/" }, [
    el("span", { class: "mark", "aria-hidden": "true", text: "词" }),
    el("span", { text: "词元写作台" }),
  ])
}

function dialog({ title, label, value = "", hint, okLabel, maxlength = "80", onOk }) {
  const errorNode = el("p", { class: "form-error", role: "alert" })
  const input = el("input", { type: "text", value, maxlength, required: "true" })
  const ok = el("button", { class: "btn btn-primary", type: "button", text: okLabel })
  const node = el("dialog", {}, [
    el("h2", { text: title }),
    el("label", {}, [label, input]),
    hint ? el("p", { class: "hint muted", text: hint }) : null,
    errorNode,
    el("div", { class: "dialog-actions" }, [
      el("button", { class: "btn", type: "button", text: "取消", onClick: () => node.close() }),
      ok,
    ]),
  ])
  ok.addEventListener("click", async () => {
    ok.disabled = true
    errorNode.textContent = ""
    try {
      await onOk(input.value)
      node.close()
    } catch (error) {
      errorNode.textContent = error.message
      ok.disabled = false
    }
  })
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") ok.click()
  })
  document.body.append(node)
  node.addEventListener("close", () => node.remove())
  node.showModal()
  input.focus()
  input.select()
}

function confirmDialog({ title, body, okLabel, onOk }) {
  const node = el("dialog", {}, [
    el("h2", { text: title }),
    el("p", { text: body }),
    el("div", { class: "dialog-actions" }, [
      el("button", { class: "btn", type: "button", text: "取消", onClick: () => node.close() }),
      el("button", {
        class: "btn btn-primary",
        type: "button",
        text: okLabel,
        onClick: async (event) => {
          event.currentTarget.disabled = true
          try {
            await onOk()
            node.close()
          } catch (error) {
            toast(error.message)
            event.currentTarget.disabled = false
          }
        },
      }),
    ]),
  ])
  document.body.append(node)
  node.addEventListener("close", () => node.remove())
  node.showModal()
}

async function showHome() {
  document.title = "项目 · 词元写作台"
  document.body.className = "view-home"
  document.body.removeAttribute("data-narrow")
  app.replaceChildren(el("p", { class: "lede", text: "正在读取项目…" }))
  try {
    paintHome((await api("/api/projects")).projects)
  } catch (error) {
    paintHome([], error.message)
  }
}

function paintHome(projects, notice) {
  const list = el("div", { class: "home-list" })
  if (notice) list.append(el("div", { class: "empty-sheet" }, [el("p", { text: notice })]))
  else if (projects.length === 0) {
    list.append(el("div", { class: "empty-sheet" }, [
      el("p", { text: "还没有项目。" }),
      el("p", { class: "muted", text: "新建一份中文文稿，或导入已有的 ZIP 项目。" }),
    ]))
  } else {
    for (const project of projects) {
      list.append(el("div", { class: "project-row" }, [
        el("a", { class: "project-open", href: `#/p/${project.id}`, text: project.name }),
        el("time", { datetime: project.updatedAt, text: formatTime(project.updatedAt) }),
        el("button", {
          class: "btn",
          type: "button",
          text: "删除",
          "aria-label": `删除项目 ${project.name}`,
          onClick: () => confirmDialog({
            title: "删除项目",
            body: `删除「${project.name}」？文件会从本机数据目录移除。`,
            okLabel: "删除",
            onOk: async () => {
              await api(`/api/projects/${project.id}`, { method: "DELETE" })
              await showHome()
            },
          }),
        }),
      ]))
    }
  }
  app.replaceChildren(
    el("header", { class: "topbar" }, [brand(), el("a", { href: "#/settings", text: "设置" })]),
    el("div", { class: "page-head" }, [
      el("div", {}, [el("h1", { text: "项目" }), el("p", { class: "lede", text: "本机写作，编译也留在这台机器上。" })]),
      el("div", { class: "actions" }, [
        el("button", { class: "btn", type: "button", text: "导入项目", onClick: importProject }),
        el("button", {
          class: "btn btn-primary",
          type: "button",
          text: "新建项目",
          onClick: () => dialog({
            title: "新建项目",
            label: "项目名称",
            value: "未命名文稿",
            hint: "将放入中文模板：ctex、公式、图片、交叉引用，以及 GB/T 7714 参考文献。",
            okLabel: "创建",
            onOk: async (name) => {
              const { project } = await api("/api/projects", { method: "POST", body: JSON.stringify({ name }) })
              location.hash = `#/p/${project.id}`
            },
          }),
        }),
      ]),
    ]),
    list,
    el("p", { class: "footer-note", text: "仅在本机使用。不开放注册，也不能把项目共享给别人。" }),
  )
}

function importProject() {
  const input = el("input", { type: "file", accept: ".zip,application/zip" })
  input.addEventListener("change", async () => {
    const file = input.files && input.files[0]
    if (!file) return
    try {
      const name = file.name.replace(/\.zip$/i, "")
      const project = (await api(`/api/projects/import?name=${encodeURIComponent(name)}`, {
        method: "POST",
        headers: { "Content-Type": "application/zip" },
        body: await file.arrayBuffer(),
      })).project
      location.hash = `#/p/${project.id}`
    } catch (error) {
      toast(error.message)
    }
  })
  input.click()
}

async function showSettings() {
  document.title = "设置 · 词元写作台"
  document.body.className = "view-settings"
  document.body.removeAttribute("data-narrow")
  app.replaceChildren(el("p", { class: "lede", text: "正在读取设置…" }))
  let meta
  try {
    meta = await api("/api/meta")
  } catch (error) {
    toast(error.message)
    location.hash = "#/"
    return
  }
  const engine = meta.engines && meta.engines.xelatex ? "已检测到 xelatex" : "未检测到 xelatex"
  const biber = meta.engines && meta.engines.biber ? "已检测到 biber" : "未检测到 biber"
  app.replaceChildren(
    el("header", { class: "topbar" }, [brand(), el("a", { href: "#/", text: "返回项目" })]),
    el("section", { class: "sheet" }, [
      el("h1", { text: "设置" }),
      el("p", { class: "muted", text: "第一版只在这台电脑上使用，界面为中文。" }),
      el("dl", {}, [
        el("dt", { text: "界面" }), el("dd", { text: "中文" }),
        el("dt", { text: "编译" }), el("dd", { text: `XeLaTeX · ${engine}` }),
        el("dt", { text: "参考文献" }), el("dd", { text: `GB/T 7714—2015 · ${biber}` }),
        el("dt", { text: "注册" }), el("dd", { text: "关闭" }),
        el("dt", { text: "共享与多人编辑" }), el("dd", { text: "不提供" }),
        el("dt", { text: "数据目录" }), el("dd", { class: "mono", text: meta.dataDir }),
        el("dt", { text: "快捷键" }), el("dd", { text: "Ctrl 或 ⌘ + S 立即保存；Ctrl 或 ⌘ + Enter 编译" }),
      ]),
    ]),
  )
}

async function leaveEditor() {
  if (!session) return
  const current = session
  clearTimeout(current.timer)
  try {
    await current.saveNow()
  } catch (error) {
    toast(error.message)
  }
  current.cleanup?.()
  if (session === current) session = null
}

async function showEditor(id) {
  if (session && session.id === id) return
  await leaveEditor()
  document.title = "编辑 · 词元写作台"
  document.body.className = "view-editor"
  app.replaceChildren(el("p", { class: "lede", text: "正在打开项目…" }))
  let payload
  try {
    payload = await api(`/api/projects/${id}/tree`)
  } catch (error) {
    toast(error.message)
    location.hash = "#/"
    return
  }
  let log = ""
  try {
    log = (await api(`/api/projects/${id}/log`)).log || ""
  } catch {
    log = ""
  }
  mountEditor(payload.project, payload.entries, log)
}

function mountEditor(project, entries, log) {
  const state = {
    project,
    entries,
    path: "",
    binary: false,
    tab: "files",
    filesOpen: true,
    pdfOpen: true,
    narrow: "source",
    logOpen: false,
    level: project.lastCompile ? project.lastCompile.level : "",
    log,
    hints: [],
    hasPdf: project.hasPdf,
    pdfToken: Date.now(),
    saveState: "已自动保存",
    compiling: false,
  }
  const shell = el("div", { class: "editor-shell" })
  const nameInput = el("input", { class: "project-name", type: "text", value: project.name, "aria-label": "项目名称", maxlength: "80" })
  const saveNode = el("span", { class: "save-state", text: state.saveState })
  const compileState = el("span", { class: "compile-state" })
  const compileButton = el("button", { class: "btn btn-compile", type: "button", text: "编译", title: "编译（Ctrl 或 ⌘ + Enter）" })
  const downloadButton = el("button", { class: "btn", type: "button", text: "下载 PDF" })
  const logButton = el("button", { class: "btn", type: "button", text: "编译日志", "aria-expanded": "false" })
  const fileToggle = el("button", { class: "btn", type: "button", text: "文件" })
  const sourceToggle = el("button", { class: "btn", type: "button", text: "源码" })
  const previewToggle = el("button", { class: "btn", type: "button", text: "预览" })
  const filePane = el("aside", { class: "file-pane" })
  const sourcePane = el("section", { class: "source-pane", "aria-label": "源码" })
  const pdfPane = el("section", { class: "pdf-pane", "aria-label": "PDF 预览" })
  const fileBody = el("div", { class: "file-scroll" })
  const outlineBody = el("div", { class: "outline-scroll" })
  const editorHost = el("div", { id: "cm" })
  const binaryNote = el("div", { class: "binary-note", hidden: "hidden" })
  const pdfStage = el("div", { class: "pdf-stage" })
  const logDrawer = el("section", { class: "log-drawer", hidden: "hidden" })
  const hintsNode = el("div", { class: "hints" })
  const rawLog = el("pre", { class: "raw-log" })
  const fileGutter = el("div", { class: "gutter gutter-files", role: "separator", "aria-orientation": "vertical", "aria-label": "调整文件栏宽度", tabindex: "0" })
  const pdfGutter = el("div", { class: "gutter gutter-pdf", role: "separator", "aria-orientation": "vertical", "aria-label": "调整预览宽度", tabindex: "0" })

  filePane.append(
    el("div", { class: "pane-tabs", role: "tablist" }, [
      el("button", { type: "button", role: "tab", text: "文件", onClick: () => { state.tab = "files"; paintTabs() } }),
      el("button", { type: "button", role: "tab", text: "大纲", onClick: () => { state.tab = "outline"; paintTabs() } }),
    ]),
    fileBody,
    outlineBody,
    el("div", { class: "pane-tools" }, [
      el("button", { class: "btn", type: "button", text: "新建文件", onClick: createFile }),
      el("button", { class: "btn", type: "button", text: "上传文件", onClick: uploadFiles }),
    ]),
  )
  sourcePane.append(editorHost, binaryNote)
  pdfPane.append(pdfStage)
  logDrawer.append(
    el("div", { class: "log-head" }, [
      el("h2", { text: "编译日志" }),
      el("span", { class: "muted", text: "常见说明在上，原始日志在下。" }),
    ]),
    hintsNode,
    rawLog,
  )
  shell.append(
    el("header", { class: "toolbar" }, [
      brand(),
      nameInput,
      saveNode,
      compileState,
      el("span", { class: "spacer" }),
      el("div", { class: "layout-switch" }, [fileToggle, sourceToggle, previewToggle]),
      logButton,
      downloadButton,
      el("a", { class: "btn", href: `/api/projects/${project.id}/export`, text: "导出项目" }),
      compileButton,
    ]),
    el("div", { class: "workspace" }, [filePane, fileGutter, sourcePane, pdfGutter, pdfPane]),
    logDrawer,
  )
  app.replaceChildren(shell)

  const cm = window.CodeMirror(editorHost, {
    value: "",
    mode: "stex",
    theme: "ciyuan",
    lineNumbers: true,
    lineWrapping: true,
    inputStyle: "textarea",
  })
  let loading = false
  let timer = 0
  let saveChain = Promise.resolve()

  const current = {
    id: project.id,
    cm,
    timer: 0,
    async saveNow() {
      if (!session || state.binary || !state.path) return
      const path = state.path
      const content = cm.getValue()
      const job = saveChain.then(async () => {
        setSave("正在保存…")
        await api(`/api/projects/${project.id}/file`, {
          method: "PUT",
          body: JSON.stringify({ path, content }),
        })
        if (session && path === state.path && content === cm.getValue()) setSave("已自动保存")
      }).catch((error) => {
        setSave("保存失败")
        throw error
      })
      saveChain = job.catch(() => {})
      return job
    },
  }
    session = current
  session.timer = 0
  session.cleanup = () => window.removeEventListener("resize", applyLayout)

  function setSave(text) {
    state.saveState = text
    saveNode.textContent = text
  }

  function paintCompile() {
    compileState.replaceChildren()
    compileButton.disabled = state.compiling
    compileButton.textContent = state.compiling ? "正在编译…" : "编译"
    downloadButton.disabled = !state.hasPdf
    if (!state.level && !state.compiling) return
    const label = state.compiling
      ? "正在编译"
      : state.level === "success"
        ? "编译完成"
        : state.level === "warning"
          ? "编译完成，有警告"
          : state.level === "error"
            ? "编译未成功"
            : ""
    if (!label) return
    const kind = state.compiling ? "running" : state.level
    compileState.append(el("span", { class: `dot ${kind}`, "aria-hidden": "true" }), el("span", { text: label }))
  }

  function paintTabs() {
    const [filesTab, outlineTab] = filePane.querySelectorAll('[role="tab"]')
    filesTab.setAttribute("aria-selected", state.tab === "files" ? "true" : "false")
    outlineTab.setAttribute("aria-selected", state.tab === "outline" ? "true" : "false")
    fileBody.hidden = state.tab !== "files"
    outlineBody.hidden = state.tab !== "outline"
  }

  function paintFiles() {
    fileBody.replaceChildren()
    const list = el("ul", { class: "file-list" })
    const groups = new Map()
    for (const entry of state.entries) {
      const slash = entry.path.lastIndexOf("/")
      const folder = slash === -1 ? "" : entry.path.slice(0, slash)
      if (!groups.has(folder)) groups.set(folder, [])
      groups.get(folder).push(entry)
    }
    for (const [folder, files] of groups) {
      if (folder) list.append(el("li", { class: "folder-label", text: folder }))
      for (const entry of files) {
        const name = entry.path.slice(folder ? folder.length + 1 : 0)
        const main = entry.path === state.project.mainFile
        list.append(el("li", {}, [
          el("button", {
            type: "button",
            class: `file-item${entry.path === state.path ? " is-active" : ""}`,
            onClick: () => openFile(entry.path),
          }, [
            el("span", { text: main ? `${name} · 主文件` : name }),
            el("small", { text: formatSize(entry.size) }),
          ]),
        ]))
      }
    }
    fileBody.append(list)
    if (state.path && state.path !== state.project.mainFile) {
      fileBody.append(el("div", { class: "pane-tools" }, [
        el("button", { class: "btn", type: "button", text: "删除此文件", onClick: deleteCurrentFile }),
      ]))
    }
  }

  function paintOutline() {
    outlineBody.replaceChildren()
    if (state.binary) {
      outlineBody.append(el("p", { class: "muted", text: "当前不是 TeX 源码。" }))
      return
    }
    const source = cm.getValue()
    const list = el("ul", { class: "outline-list" })
    const pattern = /\\(chapter|section|subsection|subsubsection)\*?\{([^}]*)\}/g
    const indent = { chapter: 0, section: 0, subsection: 12, subsubsection: 24 }
    let match
    let count = 0
    while ((match = pattern.exec(source))) {
      count += 1
      const line = source.slice(0, match.index).split("\n").length
      const title = match[2]
      list.append(el("li", {}, [
        el("button", {
          type: "button",
          class: "outline-item",
          style: `padding-left:${8 + indent[match[1]]}px`,
          text: title,
          onClick: () => {
            cm.setCursor({ line: line - 1, ch: 0 })
            cm.focus()
            if (window.matchMedia("(max-width: 960px)").matches) setNarrow("source")
          },
        }),
      ]))
    }
    outlineBody.append(count ? list : el("p", { class: "muted", text: "这份文件里没有章节标题。" }))
  }

  function paintPdf() {
    pdfStage.replaceChildren()
    if (!state.hasPdf) {
      pdfStage.append(el("div", { class: "pdf-empty" }, [
        el("p", { text: "还没有可预览的 PDF。" }),
        el("p", { class: "muted", text: "点右上角「编译」，用 XeLaTeX 生成预览。" }),
      ]))
      return
    }
    pdfStage.append(el("iframe", {
      class: "pdf-frame",
      title: "PDF 预览",
      src: `/api/projects/${project.id}/pdf?t=${state.pdfToken}#toolbar=0&navpanes=0`,
    }))
  }

  function paintLog() {
    logDrawer.hidden = !state.logOpen
    logButton.setAttribute("aria-expanded", state.logOpen ? "true" : "false")
    hintsNode.replaceChildren()
    if (state.hints.length === 0 && state.log) {
      hintsNode.append(el("p", { class: "muted", text: "日志里没有需要另作说明的常见错误。" }))
    }
    for (const hint of state.hints) {
      hintsNode.append(el("div", { class: "hint-card" }, [
        el("strong", { text: hint.title }),
        el("span", { text: hint.detail }),
      ]))
    }
    rawLog.replaceChildren()
    const lines = state.log ? state.log.split("\n") : ["还没有编译日志。"]
    lines.forEach((line, index) => {
      const match = line.match(/^((?:\.\/)?[^\s:]+\.tex):(\d+):(.*)$/)
      if (match) {
        const button = el("button", { type: "button", class: "log-jump", text: `${match[1]}:${match[2]}` })
        button.addEventListener("click", () => openAt(match[1].replace(/^\.\//, ""), Number(match[2])))
        rawLog.append(button, document.createTextNode(match[3] || ""), index === lines.length - 1 ? "" : "\n")
      } else {
        rawLog.append(line, index === lines.length - 1 ? "" : "\n")
      }
    })
  }

  function applyLayout() {
    const narrow = window.matchMedia("(max-width: 960px)").matches
    shell.classList.toggle("is-files-collapsed", !narrow && !state.filesOpen)
    shell.classList.toggle("is-pdf-collapsed", !narrow && !state.pdfOpen)
    sourceToggle.hidden = !narrow
    if (narrow) document.body.dataset.narrow = state.narrow
    else document.body.removeAttribute("data-narrow")
    fileToggle.setAttribute("aria-pressed", narrow ? String(state.narrow === "files") : String(state.filesOpen))
    previewToggle.setAttribute("aria-pressed", narrow ? String(state.narrow === "preview") : String(state.pdfOpen))
    sourceToggle.setAttribute("aria-pressed", String(state.narrow === "source"))
    requestAnimationFrame(() => cm.refresh())
  }

  function setNarrow(pane) {
    state.narrow = pane
    applyLayout()
  }

  async function openFile(filePath) {
    if (filePath === state.path && session) return
    try {
      await current.saveNow()
    } catch (error) {
      toast(error.message)
    }
    const file = await api(`/api/projects/${project.id}/file?path=${encodeURIComponent(filePath)}`)
    state.path = file.path
    state.binary = Boolean(file.binary)
    loading = true
    if (file.binary) {
      editorHost.hidden = true
      binaryNote.hidden = false
      binaryNote.replaceChildren()
      const image = [".png", ".jpg", ".jpeg"].includes(file.path.slice(file.path.lastIndexOf(".")))
      if (image) {
        binaryNote.append(el("img", { alt: file.path, src: `/api/projects/${project.id}/raw?path=${encodeURIComponent(file.path)}` }))
      }
      binaryNote.append(el("p", { text: image ? "图片会在编译时按源码引用插入。" : "这个文件不在源码区编辑。" }))
    } else {
      editorHost.hidden = false
      binaryNote.hidden = true
      cm.setValue(file.content || "")
      cm.clearHistory()
    }
    loading = false
    setSave("已自动保存")
    paintFiles()
    paintOutline()
    cm.refresh()
  }

  async function openAt(filePath, line) {
    const known = state.entries.some((entry) => entry.path === filePath)
    if (known && filePath !== state.path) await openFile(filePath)
    if (!state.binary) {
      cm.setCursor({ line: Math.max(0, line - 1), ch: 0 })
      cm.focus()
      cm.scrollIntoView({ line: Math.max(0, line - 1), ch: 0 }, 80)
      setNarrow("source")
    }
  }

  function scheduleSave() {
    if (loading || state.binary) return
    setSave("有未保存的修改")
    clearTimeout(timer)
    timer = setTimeout(() => {
      current.saveNow().catch((error) => toast(error.message))
    }, 700)
    session.timer = timer
    paintOutline()
  }

  async function compile() {
    if (state.compiling) return
    state.compiling = true
    paintCompile()
    try {
      await current.saveNow()
      const result = await api(`/api/projects/${project.id}/compile`, { method: "POST" })
      state.level = result.level
      state.hints = result.hints || []
      state.log = result.log || ""
      state.hasPdf = Boolean(result.hasPdf)
      state.pdfToken = Date.now()
      if (result.project) state.project = result.project
      if (result.level !== "success") state.logOpen = true
      paintPdf()
      paintLog()
    } catch (error) {
      state.level = "error"
      toast(error.message)
    } finally {
      state.compiling = false
      paintCompile()
    }
  }

  function createFile() {
    dialog({
      title: "新建文件",
      label: "文件路径",
      value: "notes.tex",
      hint: "可写成 chapters/intro.tex。支持 tex、bib、cls、sty、bst、txt。",
      okLabel: "创建",
      maxlength: "180",
      onOk: async (filePath) => {
        await api(`/api/projects/${project.id}/file`, {
          method: "PUT",
          body: JSON.stringify({ path: filePath.trim(), content: "" }),
        })
        state.entries = (await api(`/api/projects/${project.id}/tree`)).entries
        await openFile(filePath.trim())
      },
    })
  }

  function uploadFiles() {
    const input = el("input", { type: "file", multiple: "true" })
    input.addEventListener("change", async () => {
      try {
        for (const file of input.files || []) {
          await api(`/api/projects/${project.id}/upload?path=${encodeURIComponent(file.name)}`, {
            method: "POST",
            headers: { "Content-Type": "application/octet-stream" },
            body: await file.arrayBuffer(),
          })
        }
        state.entries = (await api(`/api/projects/${project.id}/tree`)).entries
        paintFiles()
        toast("文件已上传")
      } catch (error) {
        toast(error.message)
      }
    })
    input.click()
  }

  function deleteCurrentFile() {
    const filePath = state.path
    confirmDialog({
      title: "删除文件",
      body: `删除「${filePath}」？`,
      okLabel: "删除",
      onOk: async () => {
        await api(`/api/projects/${project.id}/file?path=${encodeURIComponent(filePath)}`, { method: "DELETE" })
        state.entries = (await api(`/api/projects/${project.id}/tree`)).entries
        await openFile(state.project.mainFile)
      },
    })
  }

  nameInput.addEventListener("change", async () => {
    const name = nameInput.value.trim()
    if (!name) {
      nameInput.value = state.project.name
      return
    }
    try {
      state.project = (await api(`/api/projects/${project.id}`, { method: "PATCH", body: JSON.stringify({ name }) })).project
      nameInput.value = state.project.name
      document.title = `${state.project.name} · 词元写作台`
    } catch (error) {
      nameInput.value = state.project.name
      toast(error.message)
    }
  })
  compileButton.addEventListener("click", compile)
  logButton.addEventListener("click", () => {
    state.logOpen = !state.logOpen
    paintLog()
  })
  downloadButton.addEventListener("click", () => {
    const link = document.createElement("a")
    link.href = `/api/projects/${project.id}/pdf?download=1&t=${Date.now()}`
    link.click()
  })
  fileToggle.addEventListener("click", () => {
    if (window.matchMedia("(max-width: 960px)").matches) setNarrow("files")
    else {
      state.filesOpen = !state.filesOpen
      applyLayout()
    }
  })
  sourceToggle.addEventListener("click", () => setNarrow("source"))
  previewToggle.addEventListener("click", () => {
    if (window.matchMedia("(max-width: 960px)").matches) setNarrow("preview")
    else {
      state.pdfOpen = !state.pdfOpen
      applyLayout()
    }
  })
  cm.on("change", scheduleSave)
  bindGutter(fileGutter, (clientX) => {
    const left = shell.querySelector(".workspace").getBoundingClientRect().left
    filePane.style.width = `${Math.min(420, Math.max(200, clientX - left))}px`
  })
  bindGutter(pdfGutter, (clientX) => {
    const box = shell.querySelector(".workspace").getBoundingClientRect()
    pdfPane.style.width = `${Math.min(box.width - 360, Math.max(280, box.right - clientX))}px`
  })
  window.addEventListener("resize", applyLayout)
  session.cleanup = () => window.removeEventListener("resize", applyLayout)

  paintTabs()
  paintFiles()
  paintPdf()
  paintLog()
  paintCompile()
  applyLayout()
  openFile(project.mainFile).catch((error) => toast(error.message))
  document.title = `${project.name} · 词元写作台`
}

function bindGutter(gutter, onDrag) {
  gutter.addEventListener("pointerdown", (event) => {
    if (window.matchMedia("(max-width: 960px)").matches) return
    event.preventDefault()
    const move = (ev) => onDrag(ev.clientX)
    const up = () => {
      window.removeEventListener("pointermove", move)
      window.removeEventListener("pointerup", up)
    }
    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", up)
  })
}

async function route() {
  const hash = location.hash || "#/"
  if (hash === "#/settings") {
    await leaveEditor()
    return showSettings()
  }
  const match = hash.match(/^#\/p\/([a-f0-9]{12})$/)
  if (match) return showEditor(match[1])
  await leaveEditor()
  return showHome()
}

window.addEventListener("hashchange", () => {
  route().catch((error) => toast(error.message))
})
window.addEventListener("keydown", (event) => {
  if (document.querySelector("dialog[open]")) return
  if (!(event.metaKey || event.ctrlKey) || !session) return
  if (event.key === "Enter") {
    event.preventDefault()
    document.querySelector(".btn-compile")?.click()
  } else if (event.key.toLowerCase() === "s") {
    event.preventDefault()
    session.saveNow().catch((error) => toast(error.message))
  }
})

route().catch((error) => toast(error.message))
