export const meta = {
  name: 'momo-build-review',
  description: 'Automate the Momo developer->reviewer loop: momo-developer implements a scoped task test-first, momo-reviewer attacks the diff and runs the suite, the developer fixes blocking findings, repeat until clean or maxRounds. Leaves a reviewed, green working tree; never commits.',
  phases: [
    { title: 'Build', detail: 'momo-developer implements the task test-first' },
    { title: 'Review', detail: 'momo-reviewer runs the suite + attacks the diff' },
    { title: 'Fix', detail: 'momo-developer addresses blocking findings' },
  ],
}

// args: a task string, or { task, maxRounds }
const task = typeof args === 'string' ? args : (args && args.task)
const MAX_ROUNDS = (args && typeof args === 'object' && args.maxRounds) || 3
if (!task) {
  throw new Error('momo-build-review needs a task: pass args as a string, or { task, maxRounds }.')
}

// A finding at these severities blocks; low/info do not.
const BLOCKING = ['critical', 'high', 'medium']

const REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['testsGreen', 'findings', 'verdict'],
  properties: {
    testsGreen: { type: 'boolean', description: 'did `swift build && swift test` pass' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'file', 'issue', 'fix'],
        properties: {
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'info'] },
          file: { type: 'string', description: 'repo-relative path' },
          line: { type: 'integer', description: '1-indexed anchor line, if applicable' },
          issue: { type: 'string' },
          fix: { type: 'string', description: 'the minimal proportionate fix' },
        },
      },
    },
    verdict: { type: 'string', description: 'one-line overall assessment' },
  },
}

function buildPrompt(t) {
  return `Read CLAUDE.md and follow it. Implement this task in the Momo repo, test-first (TDD for MomoCore logic):

${t}

Work on the real working tree. Get \`swift build\` and \`swift test\` green before you finish. Do NOT commit. When done, summarize what you changed file-by-file and paste the final test summary line.`
}

function reviewPrompt(t, devSummary) {
  return `Review the current UNCOMMITTED working-tree changes (use \`git status\` and \`git diff\`) that implement this task:

${t}

Developer's summary:
${devSummary}

First run \`swift build && swift test\` and set testsGreen accordingly — a red build/suite is itself a blocking (high) finding. Then attack the diff per your CLAUDE.md calibration: correctness, data-model invariants, the MomoCore/shell boundary, TEST ADEQUACY (would each new test actually fail if its invariant broke? — not just presence), error handling, and simplicity/over-engineering. Return every finding with a severity. Do not write fixes.`
}

function fixPrompt(t, blocking, verdict) {
  const list = blocking
    .map((f, i) => `${i + 1}. [${f.severity}] ${f.file}${f.line ? ':' + f.line : ''} — ${f.issue}\n   suggested fix: ${f.fix}`)
    .join('\n')
  return `Read CLAUDE.md. You are continuing this task:

${t}

An independent reviewer found these BLOCKING issues (reviewer verdict: "${verdict}"). Fix each in the working tree. Do NOT weaken or delete a test to make it pass; if a test is genuinely wrong, say so and justify it. Re-run \`swift build\` and \`swift test\` until green. Do NOT commit. Summarize what you changed.

${list}`
}

phase('Build')
let devSummary = await agent(buildPrompt(task), { agentType: 'momo-developer', label: 'build', phase: 'Build' })

let round = 0
while (true) {
  phase('Review')
  const review = await agent(reviewPrompt(task, devSummary), {
    agentType: 'momo-reviewer',
    label: `review r${round + 1}`,
    phase: 'Review',
    schema: REVIEW_SCHEMA,
  })

  const findings = review.findings || []
  const blocking = findings.filter(f => BLOCKING.includes(f.severity))
  const clean = review.testsGreen && blocking.length === 0
  log(`Round ${round + 1}: testsGreen=${review.testsGreen}, blocking=${blocking.length}, non-blocking=${findings.length - blocking.length} — ${review.verdict}`)

  if (clean) {
    log(`Clean after ${round + 1} review round(s). Working tree is reviewed + green — ready for a human commit.`)
    return { status: 'clean', rounds: round + 1, nonBlocking: findings.filter(f => !BLOCKING.includes(f.severity)), review, devSummary }
  }

  round++
  if (round >= MAX_ROUNDS) {
    log(`Hit maxRounds=${MAX_ROUNDS} with ${blocking.length} blocking finding(s) unresolved — human review needed.`)
    return { status: 'unresolved', rounds: round, blocking, review, devSummary }
  }

  phase('Fix')
  devSummary = await agent(fixPrompt(task, blocking, review.verdict), {
    agentType: 'momo-developer',
    label: `fix r${round}`,
    phase: 'Fix',
  })
}
