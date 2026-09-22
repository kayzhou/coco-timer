const RULES = [
  {
    re: /Undefined control sequence/i,
    title: "命令未定义",
    detail: "某处使用了 TeX 不认识的命令。请核对拼写，或确认对应宏包已经引入。",
  },
  {
    re: /Missing \$ inserted/i,
    title: "数学模式未配对",
    detail: "公式符号出现在数学模式之外。检查 $...$、\\(...\\) 或 equation 环境是否成对。",
  },
  {
    re: /File `([^']+)' not found/g,
    title: "找不到文件",
    detail: (match) => `编译器找不到「${match[1]}」。请确认文件在项目中，且路径和扩展名与引用一致。`,
  },
  {
    re: /LaTeX Error: Environment ([^ ]+) undefined/g,
    title: "环境未定义",
    detail: (match) => `环境 ${match[1]} 不存在。请检查环境名称，或引入提供它的宏包。`,
  },
  {
    re: /Citation [`']([^'`]+)[`'] on page/g,
    title: "参考文献未解析",
    detail: (match) => `引用「${match[1]}」没有进入文献表。请核对 .bib 里的文献键。`,
  },
  {
    re: /There were undefined references/i,
    title: "交叉引用未定",
    detail: "有 \\ref 还对不上 \\label。再编译一次通常可以；若仍出现，请核对标签名。",
  },
  {
    re: /Emergency stop/i,
    title: "编译已中止",
    detail: "错误使编译无法继续。请从日志里以感叹号开头的第一条看起。",
  },
  {
    re: /未找到命令 (xelatex|biber|bibtex)/,
    title: "编译工具缺失",
    detail: "本机没有所需的编译命令。XeLaTeX、Biber 以及 ctex、gb7714 宏包需要先安装。",
  },
  {
    re: /命令超时：(\S+)/,
    title: "编译超时",
    detail: (match) => `${match[1]} 运行太久，已停止。可以先缩小文档再试。`,
  },
]

export function explainLog(log) {
  if (!log) return []
  const hints = []
  const seen = new Set()
  for (const rule of RULES) {
    const flags = rule.re.flags.includes("g") ? rule.re.flags : `${rule.re.flags}g`
    const re = new RegExp(rule.re.source, flags)
    let match
    let count = 0
    while ((match = re.exec(log)) && count < 4) {
      count += 1
      if (match[0] === "") break
      const detail = typeof rule.detail === "function" ? rule.detail(match) : rule.detail
      const key = `${rule.title}\n${detail}`
      if (seen.has(key)) continue
      seen.add(key)
      hints.push({ title: rule.title, detail })
    }
  }
  return hints
}

export function compileLevel({ log, hasPdf, failed = false }) {
  const hasError = /(^|\n)! /m.test(log) || /未找到命令 /.test(log) || /命令超时/.test(log) || /\bFATAL\b/.test(log)
  const hasWarning = /\bWarning\b/.test(log) || /undefined references/i.test(log)
  if (!hasPdf || hasError || failed) return "error"
  if (hasWarning) return "warning"
  return "success"
}
