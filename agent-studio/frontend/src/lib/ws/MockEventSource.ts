import type { AgentDef } from '@/types/agent';
import type { Attachment } from '@/lib/uploads';
import type { AgentEventSource, AgentSimEvent, CommandChoices, CommandInfo, RunMode, RunSettings, UndoResult } from './types';

type Step = { delay: number; event: AgentSimEvent };

/** 실시간 글: from~to 사이에 몇 글자씩 조각(text_delta)으로 보내고, to에 완성된 글(text)을 보낸다 */
function streamText(from: number, to: number, text: string): Step[] {
  const size = 4;
  const count = Math.ceil(text.length / size);
  const steps: Step[] = Array.from({ length: count }, (_, i) => ({
    delay: Math.round(from + ((to - from) * i) / count),
    event: { type: 'tx', event: { t: 'text_delta', agent: 'main', text: text.slice(i * size, (i + 1) * size) } },
  }));
  return [...steps, { delay: to, event: { type: 'tx', event: { t: 'text', agent: 'main', text } } }];
}

const PERMISSION_ID = 'mock-deploy-permission';
const PLAN_PERMISSION_ID = 'mock-plan-approval';
/** 승인 요청에 아무 응답이 없으면 데모가 멈추지 않도록 이 시간 뒤 자동 허용 */
const PERMISSION_AUTO_ALLOW_MS = 8000;

const ROUTE_CODE = `import { Router } from 'express';
import { login, register } from '../controllers/authController.js';
import { validateBody } from '../middlewares/validate.js';

const router = Router();

router.post('/login', validateBody(['email', 'password']), login);
router.post('/register', validateBody(['email', 'password', 'name']), register);

export default router;
`;

const CONTROLLER_CODE = `import { users } from '../data/users.js';
import { issueToken } from '../utils/jwt.js';

export function login(req, res) {
  const { email, password } = req.body;
  const user = users.find((u) => u.email === email);
  if (!user || user.password !== password) {
    return res.status(401).json({ message: '이메일 또는 비밀번호가 올바르지 않습니다.' });
  }
  return res.json({ token: issueToken(user), user: { id: user.id, email: user.email } });
}

export function register(req, res) {
  const { email, password, name } = req.body;
  if (users.some((u) => u.email === email)) {
    return res.status(409).json({ message: '이미 가입된 이메일입니다.' });
  }
  const user = { id: users.length + 1, email, password, name };
  users.push(user);
  return res.status(201).json({ id: user.id, email: user.email });
}
`;

const LOGIN_FORM = `'use client';

import { useState } from 'react';

export function LoginForm({ onSubmit }: { onSubmit: (email: string, password: string) => Promise<void> }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);

  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        try {
          await onSubmit(email, password);
        } catch (err) {
          setError(err instanceof Error ? err.message : '로그인에 실패했습니다.');
        }
      }}
    >
      <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" />
      <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호" />
      {error && <p role="alert">{error}</p>}
      <button type="submit">로그인</button>
    </form>
  );
}
`;

const TEST_OUTPUT = `$ npm test

> workspace@1.0.0 test
> node --test tests/

✔ POST /auth/login 성공 시 토큰을 돌려준다 (18.2ms)
✔ POST /auth/login 비밀번호가 틀리면 401 (4.1ms)
✔ POST /auth/register 중복 이메일이면 409 (3.7ms)
✔ POST /auth/register 성공 시 201 (2.9ms)

ℹ tests 4
ℹ pass 4
ℹ fail 0
ℹ duration_ms 212.4
`;

const API_DOC = `# 인증 API

## POST /auth/login
이메일/비밀번호로 로그인하고 JWT 토큰을 발급받습니다.

| 필드 | 타입 | 필수 |
| --- | --- | --- |
| email | string | ✅ |
| password | string | ✅ |

응답 \`200\`
\`\`\`json
{ "token": "eyJhbGciOi...", "user": { "id": 1, "email": "user@example.com" } }
\`\`\`

## POST /auth/register
새 계정을 만듭니다. 이미 가입된 이메일이면 \`409\`를 돌려줍니다.
`;

const FINAL_SUMMARY = `요청하신 로그인 기능을 모두 구현했습니다.

- 백엔드: \`routes/auth.js\`, \`controllers/authController.js\` 추가 (POST /auth/login, /auth/register)
- 프론트엔드: \`components/LoginForm.tsx\` 로그인 폼 컴포넌트 작성
- 테스트: 인증 API 단위 테스트 4건 모두 통과
- 문서: \`docs/auth-api.md\` 에 API 명세 정리
- 배포: 스테이징 환경에 배포 완료

다음 단계로 비밀번호 해싱(bcrypt)과 토큰 만료 처리를 추가하는 것을 권장합니다.`;

/** 기본 7종 스크립트가 다루는 id. 그 외(사용자가 추가한 에이전트)는 generic 단계로 움직인다. */
const SCRIPTED_IDS = new Set(['plan', 'research', 'gameplay', 'world', 'test', 'doc', 'visual']);

/** 명령 하나를 받았을 때 에이전트들이 순서대로 일하는 모습을 재현하는 데모 스크립트. */
function buildScript(prompt: string, agents: AgentDef[], attachments: Attachment[]): Step[] {
  const steps: Step[] = [];
  const push = (delay: number, event: AgentSimEvent) => steps.push({ delay, event });
  const has = (id: string) => agents.some((a) => a.id === id);

  push(0, { type: 'run_start', command: prompt, workspace: '~/study/agent-studio/workspace', attachments, mode: 'cowork' });
  push(0, { type: 'session', model: 'claude-sonnet-5 (mock)' });
  push(0, { type: 'log', agent: 'system', text: `명령 접수: ${prompt}${attachments.length ? ` (첨부 ${attachments.length}개)` : ''}` });
  if (attachments.length) {
    push(600, { type: 'log', agent: 'plan', text: `첨부 파일 확인: ${attachments.map((a) => a.name).join(', ')}` });
  }

  push(200, { type: 'agent_status', agent: 'plan', status: 'thinking', room: 'work', message: '요구사항 분석 중...' });
  push(200, { type: 'log', agent: 'plan', text: '요구사항 분석 시작' });
  push(1800, { type: 'agent_status', agent: 'plan', status: 'working', message: '작업 분해 중...' });
  push(3000, { type: 'agent_status', agent: 'plan', status: 'completed', message: '분석 완료' });
  push(3000, { type: 'log', agent: 'plan', text: '요구사항 분석 완료, 작업을 분배합니다' });

  push(3200, { type: 'agent_status', agent: 'research', status: 'thinking', room: 'work', message: '관련 자료 조사 중...' });
  push(3200, { type: 'log', agent: 'research', text: '기술 조사 시작' });
  push(3200, { type: 'agent_status', agent: 'gameplay', status: 'thinking', room: 'work', message: 'API 설계 중...' });
  push(3200, { type: 'log', agent: 'gameplay', text: '백엔드 API 설계 시작' });

  push(4600, { type: 'agent_status', agent: 'research', status: 'working', message: '참고 문서 정리 중...' });
  push(4600, { type: 'agent_status', agent: 'gameplay', status: 'working', message: 'API 구현 중...', progress: 20 });
  push(4600, { type: 'log', agent: 'gameplay', text: 'API 구현 시작' });
  push(5200, {
    type: 'artifact',
    artifact: { kind: 'code', key: 'routes/auth.js', title: 'routes/auth.js', lang: 'javascript', text: ROUTE_CODE },
  });
  push(5200, { type: 'log', agent: 'gameplay', text: 'routes/auth.js 작성' });

  push(5600, { type: 'agent_status', agent: 'world', status: 'thinking', room: 'work', message: 'UI 설계 중...' });
  push(5600, { type: 'log', agent: 'world', text: '화면 작업 시작' });

  push(6600, { type: 'agent_status', agent: 'gameplay', status: 'working', message: 'API 구현 중...', progress: 55 });
  push(7000, { type: 'agent_status', agent: 'world', status: 'working', message: 'UI 컴포넌트 작업 중...' });
  push(7000, { type: 'log', agent: 'world', text: '컴포넌트 작성 중' });
  push(7600, {
    type: 'artifact',
    artifact: {
      kind: 'code',
      key: 'controllers/authController.js',
      title: 'controllers/authController.js',
      lang: 'javascript',
      text: CONTROLLER_CODE,
    },
  });
  push(7600, { type: 'log', agent: 'gameplay', text: 'controllers/authController.js 작성' });

  push(8200, { type: 'agent_status', agent: 'research', status: 'completed', message: '자료 조사 완료' });
  push(8200, { type: 'log', agent: 'research', text: '기술 조사 완료' });
  push(8400, { type: 'agent_status', agent: 'doc', status: 'thinking', room: 'work', message: '문서 작성 준비 중...' });

  push(9000, { type: 'agent_status', agent: 'gameplay', status: 'working', message: 'API 구현 중...', progress: 85 });
  push(9800, { type: 'agent_status', agent: 'gameplay', status: 'completed', message: 'API 구현 완료', progress: 100 });
  push(9800, { type: 'log', agent: 'gameplay', text: 'API 구현 완료' });

  push(10000, { type: 'agent_status', agent: 'test', status: 'thinking', room: 'work', message: '테스트 준비 중...' });
  push(10000, { type: 'log', agent: 'test', text: '테스트 실행 준비' });
  push(10400, {
    type: 'artifact',
    artifact: { kind: 'code', key: 'components/LoginForm.tsx', title: 'components/LoginForm.tsx', lang: 'tsx', text: LOGIN_FORM },
  });
  push(10400, { type: 'log', agent: 'world', text: 'components/LoginForm.tsx 작성' });
  push(10800, { type: 'agent_status', agent: 'world', status: 'completed', message: 'UI 작업 완료' });
  push(10800, { type: 'log', agent: 'world', text: '화면 작업 완료' });

  push(11200, { type: 'agent_status', agent: 'test', status: 'testing', message: '단위 테스트 실행 중...', progress: 30 });
  push(12200, { type: 'agent_status', agent: 'doc', status: 'working', message: 'API 문서 작성 중...' });
  push(13000, { type: 'agent_status', agent: 'test', status: 'testing', message: '통합 테스트 실행 중...', progress: 68 });

  push(14200, { type: 'agent_status', agent: 'doc', status: 'completed', message: '문서화 완료' });
  push(14200, { type: 'artifact', artifact: { kind: 'doc', key: 'docs/auth-api.md', title: 'docs/auth-api.md', lang: 'markdown', text: API_DOC } });
  push(14200, { type: 'log', agent: 'doc', text: 'docs/auth-api.md 작성 완료' });
  push(14600, { type: 'agent_status', agent: 'test', status: 'testing', message: '테스트 마무리 중...', progress: 100 });
  push(15200, { type: 'agent_status', agent: 'test', status: 'completed', message: '모든 테스트 통과' });
  push(15200, { type: 'artifact', artifact: { kind: 'test', key: 'bash:npm test', title: 'npm test', lang: 'bash', text: TEST_OUTPUT } });
  push(15200, { type: 'log', agent: 'test', text: '모든 테스트 통과 (4/4)' });

  // 사용자가 추가한 에이전트: 테스트 단계 즈음에 차례로 자기 작업실에 가서 일한다
  agents
    .filter((a) => !SCRIPTED_IDS.has(a.id))
    .forEach((a, i) => {
      const t0 = 11000 + i * 700;
      push(t0, { type: 'agent_status', agent: a.id, status: 'thinking', room: 'work', message: `${a.taskLabel} 준비 중...` });
      push(t0, { type: 'log', agent: a.id, text: `${a.taskLabel} 시작` });
      push(t0 + 1200, { type: 'agent_status', agent: a.id, status: 'working', message: `${a.taskLabel} 진행 중...`, progress: 35 });
      push(t0 + 2400, { type: 'agent_status', agent: a.id, status: 'working', message: `${a.taskLabel} 진행 중...`, progress: 75 });
      push(t0 + 3400, { type: 'agent_status', agent: a.id, status: 'completed', message: `${a.taskLabel} 완료`, progress: 100 });
      push(t0 + 3400, { type: 'log', agent: a.id, text: `${a.taskLabel} 완료` });
    });

  if (!has('visual')) {
    push(15600, {
      type: 'run_done',
      result: {
        ok: true,
        result: FINAL_SUMMARY.replace('- 배포: 스테이징 환경에 배포 완료', '- 배포: 배포 에이전트가 없어 건너뜀'),
        costUsd: 0.0412,
        turns: 22,
        durationMs: 15600,
      },
    });
    push(15600, { type: 'log', agent: 'system', text: '모든 에이전트가 작업을 완료했습니다.' });
    return steps;
  }

  push(15400, { type: 'agent_status', agent: 'visual', status: 'thinking', room: 'work', message: '배포 준비 중...' });
  push(15400, { type: 'log', agent: 'visual', text: '배포 준비 시작' });
  push(16200, {
    type: 'permission_request',
    request: {
      id: PERMISSION_ID,
      agent: 'visual',
      tool: 'Bash',
      title: '스테이징 서버에 배포 명령 실행',
      detail: 'npm run deploy:staging',
      canAlwaysAllow: true,
    },
  });
  push(16200, { type: 'log', agent: 'visual', text: '배포 명령 실행 승인을 기다립니다' });

  return steps;
}

const CODE_PLAN = `1. src/routes/auth.js 의 로그인/회원가입 라우트에 입력 검증 미들웨어를 붙인다
2. src/middlewares/validate.js 를 새로 만들어 필수 필드·이메일 형식을 검사한다
3. 실패 시 400과 필드별 메시지를 돌려준다
4. tests/auth.test.js 에 검증 실패 케이스 2건을 추가하고 npm test 로 확인한다`;

const VALIDATE_CODE = `export function validateBody(required) {
  return (req, res, next) => {
    const missing = required.filter((k) => !req.body?.[k]);
    if (missing.length) return res.status(400).json({ message: '필수 값이 없습니다.', fields: missing });
    if (req.body.email && !/^[^@\\s]+@[^@\\s]+$/.test(req.body.email)) {
      return res.status(400).json({ message: '이메일 형식이 올바르지 않습니다.', fields: ['email'] });
    }
    return next();
  };
}
`;

const CODE_SUMMARY = '로그인/회원가입 요청에 입력 검증을 추가했습니다.\n- `src/middlewares/validate.js`: 필수 필드·이메일 형식 검사 (실패 시 400)\n- `src/routes/auth.js`: 두 라우트에 검증 연결\n- `npm test`: 4건 모두 통과';

/**
 * 코드 모드 데모: 서브에이전트 없이 Claude 혼자 파일을 읽고 고치고 테스트한다 (로그는 system 줄로 흐른다).
 * 이어서 대화 중이면 continued로 시작하고, 계획 먼저면 계획 승인(ExitPlanMode)에서 멈춘다.
 */
function buildCodeScript(prompt: string, attachments: Attachment[], continued: boolean, planFirst: boolean): Step[] {
  const steps: Step[] = [];
  const push = (delay: number, event: AgentSimEvent) => steps.push({ delay, event });
  push(0, { type: 'run_start', command: prompt, workspace: '~/study/agent-studio/workspace', attachments, mode: 'code', continued, planFirst });
  push(0, { type: 'session', model: 'claude-sonnet-5 (mock)' });
  push(0, { type: 'log', agent: 'system', text: `코드 명령 접수: ${prompt}${continued ? ' (이어서)' : ''}` });
  if (!continued) push(100, { type: 'conversation', mode: 'code', active: true, id: 'mock-code', title: prompt });
  steps.push(...streamText(100, 450, '먼저 인증 라우트와 기존 검증 코드를 확인하겠습니다.'));
  push(500, { type: 'log', agent: 'system', text: '파일 읽는 중: src/routes/auth.js' });
  push(500, { type: 'tx', event: { t: 'tool_start', id: 'mock-read', agent: 'main', tool: 'Read', label: '파일 읽기: src/routes/auth.js', detail: { kind: 'read', path: 'src/routes/auth.js' } } });
  push(800, { type: 'tx', event: { t: 'tool_done', id: 'mock-read', ok: true } });
  push(1100, { type: 'log', agent: 'system', text: '검색: validateBody' });
  push(1100, { type: 'tx', event: { t: 'tool_start', id: 'mock-grep', agent: 'main', tool: 'Grep', label: '코드 검색: validateBody', detail: { kind: 'search', pattern: 'validateBody', path: 'src' } } });
  push(1400, { type: 'tx', event: { t: 'tool_done', id: 'mock-grep', ok: true, output: 'src/routes/auth.js' } });
  if (planFirst) {
    push(1800, { type: 'log', agent: 'system', text: '계획을 세웠습니다. 승인을 기다립니다' });
    push(1800, {
      type: 'permission_request',
      request: { id: PLAN_PERMISSION_ID, agent: 'system', tool: 'ExitPlanMode', title: '계획 승인 — 승인하면 이 계획대로 수정을 시작합니다', detail: CODE_PLAN, canAlwaysAllow: false },
    });
    return steps;
  }
  return [...steps, ...buildCodeTail(1800)];
}

function buildCodeTail(start: number): Step[] {
  const steps: Step[] = [];
  const push = (delay: number, event: AgentSimEvent) => steps.push({ delay, event });
  push(start, {
    type: 'tx',
    event: { t: 'plan', items: [{ text: '검증 미들웨어 만들기', status: 'in_progress' }, { text: '라우트에 연결', status: 'pending' }, { text: '테스트 실행', status: 'pending' }] },
  });
  push(start, { type: 'tx', event: { t: 'text', agent: 'main', text: '검증 미들웨어가 없어서 `src/middlewares/validate.js`를 새로 만들겠습니다.' } });
  push(start, { type: 'tx', event: { t: 'tool_start', id: 'mock-write', agent: 'main', tool: 'Write', label: '파일 생성: src/middlewares/validate.js', detail: { kind: 'write', path: 'src/middlewares/validate.js', content: VALIDATE_CODE } } });
  push(start + 300, { type: 'tx', event: { t: 'tool_done', id: 'mock-write', ok: true } });
  push(start, { type: 'log', agent: 'system', text: '수정: src/middlewares/validate.js' });
  push(start, { type: 'artifact', artifact: { kind: 'code', key: 'src/middlewares/validate.js', title: 'src/middlewares/validate.js', lang: 'JavaScript', text: VALIDATE_CODE } });
  push(start + 900, {
    type: 'tx',
    event: { t: 'plan', items: [{ text: '검증 미들웨어 만들기', status: 'completed' }, { text: '라우트에 연결', status: 'in_progress' }, { text: '테스트 실행', status: 'pending' }] },
  });
  push(start + 900, {
    type: 'tx',
    event: {
      t: 'tool_start',
      id: 'mock-edit',
      agent: 'main',
      tool: 'Edit',
      label: '파일 수정: src/routes/auth.js',
      detail: {
        kind: 'edit',
        path: 'src/routes/auth.js',
        edits: [
          {
            oldText: "router.post('/login', login);\nrouter.post('/register', register);",
            newText: "router.post('/login', validateBody(['email', 'password']), login);\nrouter.post('/register', validateBody(['email', 'password', 'name']), register);",
          },
        ],
      },
    },
  });
  push(start + 1200, { type: 'tx', event: { t: 'tool_done', id: 'mock-edit', ok: true } });
  push(start + 900, { type: 'log', agent: 'system', text: '수정: src/routes/auth.js' });
  push(start + 900, { type: 'artifact', artifact: { kind: 'code', key: 'src/routes/auth.js', title: 'src/routes/auth.js', lang: 'JavaScript', text: ROUTE_CODE } });
  push(start + 1800, {
    type: 'tx',
    event: { t: 'plan', items: [{ text: '검증 미들웨어 만들기', status: 'completed' }, { text: '라우트에 연결', status: 'completed' }, { text: '테스트 실행', status: 'in_progress' }] },
  });
  push(start + 1800, { type: 'tx', event: { t: 'tool_start', id: 'mock-bash', agent: 'main', tool: 'Bash', label: '명령 실행: npm test', detail: { kind: 'bash', command: 'npm test', description: '테스트 실행' } } });
  push(start + 3000, { type: 'tx', event: { t: 'tool_done', id: 'mock-bash', ok: true, output: TEST_OUTPUT } });
  push(start + 3100, {
    type: 'tx',
    event: { t: 'plan', items: [{ text: '검증 미들웨어 만들기', status: 'completed' }, { text: '라우트에 연결', status: 'completed' }, { text: '테스트 실행', status: 'completed' }] },
  });
  steps.push(...streamText(start + 3100, start + 3950, CODE_SUMMARY));
  push(start + 1800, { type: 'log', agent: 'system', text: '실행: npm test' });
  push(start + 3000, { type: 'artifact', artifact: { kind: 'test', key: 'bash:npm test', title: 'npm test', lang: 'bash', text: TEST_OUTPUT } });
  push(start + 4000, {
    type: 'run_done',
    result: {
      ok: true,
      result: CODE_SUMMARY,
      costUsd: 0.0213,
      turns: 9,
      durationMs: start + 4000,
      suggestions: ['검증 실패 케이스 테스트를 추가해줘', '비밀번호 최소 길이 검사를 넣어줘', '에러 응답 형식을 문서로 정리해줘'],
    },
  });
  push(start + 4000, { type: 'log', agent: 'system', text: '작업을 마쳤습니다. (9턴, $0.0213)' });
  push(start + 4100, {
    type: 'tx',
    event: {
      t: 'checkpoint',
      id: `mock-cp-${Date.now()}`,
      files: [
        { path: 'src/middlewares/validate.js', status: 'added' },
        { path: 'src/routes/auth.js', status: 'modified' },
      ],
    },
  });
  return steps;
}

const CHAT_ANSWER = '(Mock) 인증 라우트는 `src/routes/auth.js`에 있고, 컨트롤러가 이메일로 사용자를 찾아 비밀번호를 비교한 뒤 토큰을 발급합니다. 비밀번호가 **평문**으로 저장돼 있어 해싱을 권합니다.';

/** 채팅 모드 데모: 파일만 읽고 답한다 */
function buildChatScript(prompt: string, attachments: Attachment[], continued: boolean): Step[] {
  return [
    { delay: 0, event: { type: 'run_start', command: prompt, workspace: '~/study/agent-studio/workspace', attachments, mode: 'chat', continued } },
    { delay: 0, event: { type: 'session', model: 'claude-sonnet-5 (mock)' } },
    { delay: 0, event: { type: 'log', agent: 'system', text: `채팅 접수: ${prompt}${continued ? ' (이어서)' : ''}` } },
    ...(continued ? [] : [{ delay: 100, event: { type: 'conversation', mode: 'chat', active: true, id: 'mock-chat', title: prompt } as AgentSimEvent }]),
    { delay: 700, event: { type: 'log', agent: 'system', text: '파일 읽는 중: src/routes/auth.js' } },
    { delay: 700, event: { type: 'tx', event: { t: 'tool_start', id: 'mock-chat-read', agent: 'main', tool: 'Read', label: '파일 읽기', detail: { kind: 'read', path: 'src/routes/auth.js' } } } },
    { delay: 1000, event: { type: 'tx', event: { t: 'tool_done', id: 'mock-chat-read', ok: true } } },
    ...streamText(1050, 1550, CHAT_ANSWER),
    {
      delay: 1600,
      event: {
        type: 'run_done',
        result: {
          ok: true,
          result: CHAT_ANSWER,
          costUsd: 0.0041,
          turns: 2,
          durationMs: 1600,
          suggestions: ['비밀번호 해싱을 추가해줘', '토큰 만료 처리는 어떻게 돼 있어?'],
        },
      },
    },
  ];
}

/** 승인 이후 이어지는 배포 마무리 스크립트 */
function buildDeployTail(allowed: boolean): Step[] {
  const steps: Step[] = [];
  const push = (delay: number, event: AgentSimEvent) => steps.push({ delay, event });

  if (!allowed) {
    push(0, { type: 'agent_status', agent: 'visual', status: 'error', message: '배포가 거부되었습니다' });
    push(0, { type: 'log', agent: 'visual', text: '배포 명령이 거부되어 배포를 건너뜁니다' });
    push(600, {
      type: 'run_done',
      result: {
        ok: true,
        result: FINAL_SUMMARY.replace('- 배포: 스테이징 환경에 배포 완료', '- 배포: 사용자가 거부하여 건너뜀'),
        costUsd: 0.0421,
        turns: 23,
        durationMs: 17400,
      },
    });
    push(600, { type: 'log', agent: 'system', text: '배포를 제외한 모든 작업을 완료했습니다.' });
    return steps;
  }

  push(0, { type: 'agent_status', agent: 'visual', status: 'deploying', message: '스테이징 배포 중...', progress: 42 });
  push(1200, { type: 'agent_status', agent: 'visual', status: 'deploying', message: '스테이징 배포 중...', progress: 80 });
  push(2200, { type: 'agent_status', agent: 'visual', status: 'completed', message: '배포 완료', progress: 100 });
  push(2200, { type: 'log', agent: 'visual', text: '스테이징 배포 완료' });
  push(2600, { type: 'run_done', result: { ok: true, result: FINAL_SUMMARY, costUsd: 0.0487, turns: 26, durationMs: 19200 } });
  push(2600, { type: 'log', agent: 'system', text: '모든 에이전트가 작업을 완료했습니다.' });
  return steps;
}

/** Mock 모드에서 흉내 내는 슬래시 명령 (Live 모드에서는 서버가 처리) */
const MOCK_COMMANDS: CommandInfo[] = [
  { name: 'discuss', description: 'Codex와 대화·작업 요청 (기본)', argumentHint: '<메시지>', source: 'builtin', scope: 'codex' },
  { name: 'review', description: '코드 리뷰 (읽기 전용)', argumentHint: '<메시지>', source: 'builtin', scope: 'codex' },
  { name: 'implement', description: '구현 요청 (파일 수정)', argumentHint: '<메시지>', source: 'builtin', scope: 'codex' },
  { name: 'model', description: 'Codex 모델 보기/변경', argumentHint: '[model|default]', source: 'builtin', scope: 'codex' },
  { name: 'status', description: 'Codex 상태', argumentHint: '', source: 'builtin', scope: 'codex' },
  { name: 'reset', description: 'Codex 직접 대화 기억 초기화', argumentHint: '', source: 'builtin', scope: 'codex' },
  { name: 'help', description: '사용할 수 있는 명령 목록', argumentHint: '', source: 'builtin' },
  { name: 'model', description: '실행에 쓸 모델 보기/변경 (예: /model opus)', argumentHint: '[model]', source: 'builtin' },
  {
    name: 'codex',
    description: 'Codex 에이전트에게 직접 말하기 (예: /codex 이 설계 어때?)',
    argumentHint: '[discuss|review|implement|image] [@에이전트] [>저장경로] <메시지> | reset',
    source: 'builtin',
  },
  { name: 'workspace', description: '에이전트가 작업할 폴더 보기/변경 (예: /workspace ~/projects/my-app)', argumentHint: '[path|default]', source: 'builtin' },
  { name: 'effort', description: '추론 노력 수준 보기/변경', argumentHint: '[low|medium|high|xhigh|max|off]', source: 'builtin' },
  { name: 'permission-mode', description: '권한 모드 보기/변경', argumentHint: '[acceptEdits|default]', source: 'builtin' },
  { name: 'settings', description: '현재 실행 설정 전체 보기', argumentHint: '', source: 'builtin' },
  { name: 'agents', description: '등록된 서브에이전트 목록', argumentHint: '', source: 'builtin' },
  { name: 'usage', description: 'Claude 구독 사용량 (5시간/7일 한도 소진율)', argumentHint: '', source: 'builtin' },
  { name: 'cost', description: '실행 비용/토큰 (마지막 실행, 오늘, 전체 누적, 모델별)', argumentHint: '', source: 'builtin' },
  { name: 'context', description: '다음 실행이 시작할 때의 컨텍스트 창 사용량', argumentHint: '', source: 'builtin' },
  { name: 'clear', description: '로그와 결과 화면 비우기', argumentHint: '', source: 'builtin' },
];

export class MockEventSource implements AgentEventSource {
  private timers: ReturnType<typeof setTimeout>[] = [];
  private settings: RunSettings = { workspaceDir: '/Users/me/study/agent-studio/workspace', permissionMode: 'acceptEdits', maxTurns: 60, maxBudgetUsd: 2 };
  private onEvent: ((evt: AgentSimEvent) => void) | null = null;
  private pendingPermission: string | null = null;
  private alwaysAllow = false;
  /** 모드별로 이어갈 대화가 있는지 (Live 서버의 세션 기억을 흉내) */
  private conversations: Partial<Record<RunMode, boolean>> = {};
  /** 데모용 컨텍스트 사용량 (명령마다 늘고 압축하면 줄어든다) */
  private contextPct: Partial<Record<RunMode, number>> = {};
  private running = false;

  connect(onEvent: (evt: AgentSimEvent) => void) {
    this.onEvent = onEvent;
    onEvent({ type: 'connection', status: 'connected' });
  }

  disconnect() {
    this.clearTimers();
    this.onEvent = null;
  }

  sendCommand(prompt: string, agents: AgentDef[], attachments: Attachment[] = [], mode: RunMode = 'code', opts: { planFirst?: boolean } = {}) {
    if (!this.onEvent) return;
    if (/^\/compact\b/i.test(prompt.trim()) && (mode === 'code' || mode === 'chat')) {
      this.compact(mode);
      return;
    }
    if (/^\/[a-zA-Z]/.test(prompt.trim())) {
      this.handleSlash(prompt.trim(), agents);
      return;
    }
    this.clearTimers();
    this.pendingPermission = null;
    this.running = true;

    if (mode === 'code' || mode === 'chat') {
      const continued = !!this.conversations[mode];
      this.conversations[mode] = true;
      const script = mode === 'code' ? buildCodeScript(prompt, attachments, continued, !!opts.planFirst) : buildChatScript(prompt, attachments, continued);
      this.schedule(script, (evt) => {
        if (evt.type === 'permission_request') this.pendingPermission = evt.request.id;
        if (evt.type === 'run_done') {
          this.running = false;
          this.reportContext(mode, Math.min(96, (this.contextPct[mode] ?? 8) + 38));
        }
        return true;
      });
      return;
    }

    this.schedule(buildScript(prompt, agents, attachments), (evt) => {
      if (evt.type === 'permission_request') {
        if (this.alwaysAllow) {
          // 이전에 "항상 허용"을 눌렀으면 묻지 않고 바로 진행
          this.onEvent?.({ type: 'log', agent: 'system', text: '이전 승인에 따라 자동 허용했습니다.' });
          this.schedule(buildDeployTail(true));
          return false;
        }
        this.pendingPermission = evt.request.id;
        this.timers.push(setTimeout(() => this.replyPermission(evt.request.id, true, false), PERMISSION_AUTO_ALLOW_MS));
      }
      return true;
    });
  }

  private reportContext(mode: RunMode, pct: number) {
    this.contextPct[mode] = pct;
    const max = 200_000;
    this.onEvent?.({ type: 'context_usage', mode, id: `mock-${mode}`, context: { tokens: Math.round((max * pct) / 100), max, pct, at: Date.now() } });
  }

  /** 데모 대화 압축: 요약했다는 경계를 남기고 게이지를 줄인다 */
  private compact(mode: RunMode) {
    if (!this.conversations[mode]) {
      this.onEvent?.({ type: 'log', agent: 'system', text: '압축할 대화가 없습니다. 먼저 명령을 실행하세요.' });
      return;
    }
    const pre = Math.round((200_000 * (this.contextPct[mode] ?? 40)) / 100);
    this.clearTimers();
    this.running = true;
    this.schedule(
      [
        { delay: 0, event: { type: 'run_start', command: '/compact', workspace: '~/study/agent-studio/workspace', attachments: [], mode, continued: true } },
        { delay: 900, event: { type: 'tx', event: { t: 'compacted', trigger: 'manual', preTokens: pre, postTokens: 9_400 } } },
        { delay: 1000, event: { type: 'run_done', result: { ok: true, result: '', costUsd: 0.0041, turns: 1, durationMs: 1000 } } },
      ],
      (evt) => {
        if (evt.type === 'run_done') {
          this.running = false;
          this.reportContext(mode, 5);
        }
        return true;
      },
    );
  }

  followUp(prompt: string) {
    if (!this.onEvent) return;
    if (!this.running) {
      this.onEvent({ type: 'log', agent: 'system', text: '추가 지시 실패: 실행 중인 작업이 없습니다.' });
      return;
    }
    this.onEvent({ type: 'follow_up', text: prompt });
    this.onEvent({ type: 'log', agent: 'system', text: `추가 지시: ${prompt} (Mock: 다음 단계에 반영된 것으로 봅니다)` });
  }

  async undoCheckpoint(id: string): Promise<UndoResult> {
    // Mock: 실제 파일은 없으니 되돌린 것으로만 보여준다
    const restored = ['src/middlewares/validate.js', 'src/routes/auth.js'];
    this.onEvent?.({ type: 'tx', event: { t: 'checkpoint_undone', id, restored, skipped: [], complete: true } });
    this.onEvent?.({ type: 'log', agent: 'system', text: `실행 되돌리기: ${restored.length}개 복원 (Mock)` });
    return { ok: true, restored, skipped: [], complete: true };
  }

  newConversation(mode?: RunMode) {
    if (!this.onEvent) return;
    if (this.running) {
      this.onEvent({ type: 'log', agent: 'system', text: '새 대화 실패: 실행 중에는 새 대화를 시작할 수 없습니다.' });
      return;
    }
    for (const m of mode ? [mode] : (['code', 'chat', 'cowork'] as RunMode[])) {
      this.conversations[m] = false;
      this.onEvent({ type: 'conversation', mode: m, active: false });
    }
  }

  interrupt() {
    if (!this.onEvent) return;
    this.running = false;
    this.clearTimers();
    this.pendingPermission = null;
    this.onEvent({ type: 'run_aborted' });
    this.onEvent({ type: 'log', agent: 'system', text: '사용자가 작업을 중단했습니다.' });
  }

  replyPermission(id: string, allowed: boolean, always: boolean | 'all') {
    if (!this.onEvent || this.pendingPermission !== id) return;
    this.pendingPermission = null;
    if (id === PLAN_PERMISSION_ID) {
      this.onEvent({ type: 'permission_resolved', id, allowed });
      if (allowed) {
        this.schedule(buildCodeTail(300), (evt) => {
          if (evt.type === 'run_done') this.running = false;
          return true;
        });
      } else {
        this.running = false;
        this.onEvent({ type: 'run_done', result: { ok: true, result: '계획을 승인하지 않아 파일을 고치지 않았습니다. 바꾸고 싶은 점을 알려주시면 계획을 다시 세우겠습니다.', costUsd: 0.006, turns: 3, durationMs: 2000 } });
      }
      return;
    }
    if (allowed && always) this.alwaysAllow = true;
    this.onEvent({ type: 'permission_resolved', id, allowed });
    this.schedule(buildDeployTail(allowed));
  }

  async listCommands(): Promise<CommandInfo[]> {
    return MOCK_COMMANDS;
  }

  private handleSlash(text: string, agents: AgentDef[]) {
    const emit = (evt: AgentSimEvent) => this.onEvent?.(evt);
    const reply = (ok: boolean, body: string, choices?: CommandChoices) => emit({ type: 'command_result', command: text, ok, text: body, choices });
    const m = /^\/([a-zA-Z][\w-]*)\s*([\s\S]*)$/.exec(text);
    const name = m?.[1].toLowerCase() ?? '';
    const arg = m?.[2].trim() ?? '';
    const s = this.settings;
    switch (name) {
      case 'help':
        reply(
          true,
          [
            '사용할 수 있는 명령 (Mock):',
            ...MOCK_COMMANDS.filter((c) => !c.scope).map((c) => `/${c.name}${c.argumentHint ? ` ${c.argumentHint}` : ''} — ${c.description}`),
          ].join('\n'),
        );
        return;
      case 'model':
        if (!arg) {
          const models = [
            { value: 'default', label: '기본값 (Claude Code 설정)' },
            { value: 'sonnet', label: 'Sonnet (claude-sonnet-5)', description: '일상 작업에 효율적' },
            { value: 'opus', label: 'Opus (claude-opus-5)', description: '복잡한 작업에 강함' },
            { value: 'haiku', label: 'Haiku (claude-haiku-4-5)', description: '가장 빠르고 저렴' },
          ];
          return reply(true, `현재 모델: ${s.model ?? '기본값'}\n사용 가능한 모델: default, sonnet, opus, haiku\n바꾸려면 /model <이름>`, {
            command: '/model',
            title: '모델 선택',
            options: models.map((m) => ({ ...m, current: (s.model ?? 'default') === m.value })),
          });
        }
        this.settings = { ...s, model: arg === 'default' ? undefined : arg };
        emit({ type: 'settings', settings: this.settings });
        return reply(true, arg === 'default' ? '모델을 기본값으로 되돌렸습니다.' : `모델을 ${arg}(으)로 바꿨습니다. (Mock: 실제 실행에는 영향 없음)`);
      case 'codex': {
        const codex = agents.find((a) => a.provider === 'codex');
        if (!arg) return reply(true, 'Codex 에이전트에게 직접 메시지를 보냅니다 (Mock).\n/codex <메시지>, /codex review <메시지>, /codex reset');
        if (!codex) return reply(false, '등록된 Codex 에이전트가 없습니다. 에이전트 추가에서 제공자를 Codex로 선택하세요.');
        const message = arg.replace(/^(discuss|review|implement)\s+/, '').replace(/^@\S+\s+/, '');
        emit({ type: 'log', agent: 'system', text: `사용자 → ${codex.id} [토론]: ${message}` });
        emit({ type: 'agent_status', agent: codex.id, status: 'thinking', room: 'work', message: `[토론] ${message.slice(0, 40)}` });
        this.timers.push(
          setTimeout(() => {
            const answer = '(Mock) 방향은 좋습니다. 단, 상태를 한 곳에서 관리하고 실패 경로 테스트를 먼저 추가하는 걸 권합니다.';
            emit({ type: 'agent_status', agent: codex.id, status: 'completed', message: answer, progress: 100 });
            emit({ type: 'log', agent: codex.id, text: answer });
            reply(true, `${codex.shortName}:\n${answer}`);
          }, 1200),
        );
        return;
      }
      case 'workspace':
      case 'cwd':
        if (!arg) return reply(true, `현재 작업 폴더: ${s.workspaceDir}\n바꾸려면 /workspace <경로>, 기본값으로 되돌리려면 /workspace default`);
        this.settings = { ...s, workspaceDir: arg === 'default' ? '/Users/me/study/agent-studio/workspace' : arg };
        emit({ type: 'settings', settings: this.settings });
        return reply(true, `작업 폴더를 ${this.settings.workspaceDir}(으)로 바꿨습니다. (Mock: 실제 실행에는 영향 없음)`);
      case 'effort':
        if (!arg) {
          return reply(true, `현재 추론 노력: ${s.effort ?? '기본값'}`, {
            command: '/effort',
            title: '추론 노력 선택',
            options: ['off', 'low', 'medium', 'high', 'xhigh', 'max'].map((l) => ({ value: l, label: l === 'off' ? '기본값' : l, current: (s.effort ?? 'off') === l })),
          });
        }
        if (!['low', 'medium', 'high', 'xhigh', 'max', 'off'].includes(arg)) return reply(false, 'effort는 low, medium, high, xhigh, max 중 하나여야 합니다.');
        this.settings = { ...s, effort: arg === 'off' ? undefined : (arg as RunSettings['effort']) };
        emit({ type: 'settings', settings: this.settings });
        return reply(true, `추론 노력을 ${arg}(으)로 바꿨습니다.`);
      case 'permission-mode':
        if (!arg) {
          return reply(true, `현재 권한 모드: ${s.permissionMode}`, {
            command: '/permission-mode',
            title: '권한 모드 선택',
            options: [
              { value: 'acceptEdits', label: 'acceptEdits', description: '파일 수정 자동 허용, 명령 실행은 승인', current: s.permissionMode === 'acceptEdits' },
              { value: 'default', label: 'default', description: '모두 승인', current: s.permissionMode === 'default' },
            ],
          });
        }
        if (arg !== 'acceptEdits' && arg !== 'default') return reply(false, '권한 모드는 acceptEdits, default 중 하나여야 합니다.');
        this.settings = { ...s, permissionMode: arg };
        emit({ type: 'settings', settings: this.settings });
        return reply(true, `권한 모드를 ${arg}(으)로 바꿨습니다.`);
      case 'settings':
        return reply(
          true,
          `- 작업 폴더: ${s.workspaceDir}\n- 모델: ${s.model ?? '기본값'}\n- 추론 노력: ${s.effort ?? '기본값'}\n- 권한 모드: ${s.permissionMode}\n- 비용 한도: $${s.maxBudgetUsd}\n- 최대 턴: ${s.maxTurns}`,
        );
      case 'agents':
        return reply(true, ['등록된 서브에이전트:', ...agents.map((a) => `- ${a.sdkName} (${a.name}): ${a.sdkDescription}`)].join('\n'));
      case 'usage':
        return reply(
          true,
          '구독: pro (Mock)\n5시간 한도          32% [██████░░░░░░░░░░░░░░] · 2시간 10분 뒤 초기화\n주간 한도(7일)       12% [██░░░░░░░░░░░░░░░░░░] · 4일 6시간 뒤 초기화',
        );
      case 'cost':
        return reply(
          true,
          '마지막 실행: $0.0487 · 26턴 · 19초 (Mock)\n오늘: $0.0487 · 1회 실행\n전체: $0.0487 · 1회 실행\n\n※ Mock 모드의 가짜 값입니다. Live 모드에서는 실제 실행 기록을 보여줍니다.',
        );
      case 'context':
        return reply(
          true,
          '모델: claude-sonnet-5 (Mock)\n컨텍스트: 14k / 1000k 토큰 (1%)\n\n구성:\n  System prompt   4.2k  0.4%\n  System tools    7.3k  0.7%\n  Custom agents    482  0.0%\n  Free space      953k 95.3% (여유)\n\n※ Mock 모드의 가짜 값입니다.',
        );
      case 'clear':
        this.clearTimers();
        this.pendingPermission = null;
        this.running = false;
        this.conversations = {};
        emit({ type: 'cleared' });
        return reply(true, '로그와 결과를 비웠습니다.');
      default:
        return reply(false, `Mock 모드에서는 /${name} 명령을 지원하지 않습니다. Live 모드에서는 Claude Code에 전달됩니다.`);
    }
  }

  /** 스텝을 예약한다. beforeEmit이 false를 돌려주면 그 이벤트는 내보내지 않는다. */
  private schedule(script: Step[], beforeEmit?: (evt: AgentSimEvent) => boolean) {
    for (const step of script) {
      const t = setTimeout(() => {
        if (beforeEmit && !beforeEmit(step.event)) return;
        if (step.event.type === 'run_done') this.running = false;
        this.onEvent?.(step.event);
      }, step.delay);
      this.timers.push(t);
    }
  }

  private clearTimers() {
    for (const t of this.timers) clearTimeout(t);
    this.timers = [];
  }
}
