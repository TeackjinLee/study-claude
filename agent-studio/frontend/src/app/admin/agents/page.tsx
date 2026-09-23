'use client';

import { useEffect } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { AgentListPanel } from '@/components/agent-office/AgentListPanel';
import { StatusSummaryPanel } from '@/components/agent-office/StatusSummaryPanel';
import { OfficeStage } from '@/components/agent-office/OfficeStage';
import { CommandBar } from '@/components/agent-office/CommandBar';
import { SelectedAgentPanel } from '@/components/agent-office/SelectedAgentPanel';
import { LogPanel } from '@/components/agent-office/LogPanel';
import { TaskProgressPanel } from '@/components/agent-office/TaskProgressPanel';
import { TaskGraphPanel } from '@/components/agent-office/TaskGraphPanel';
import { ResultsPanel } from '@/components/agent-office/ResultsPanel';
import { PermissionBanner } from '@/components/agent-office/PermissionBanner';
import { CenterViewTabs } from '@/components/agent-office/CenterViewTabs';
import { AgentEditorDialog } from '@/components/agent-office/AgentEditorDialog';
import { ChoiceDialog } from '@/components/agent-office/ChoiceDialog';

/**
 * 시안(workspace/agent_ad.png)의 3단 레이아웃.
 *  좌: 에이전트 목록 / 전체 상태
 *  중: 사무실 맵 + (명령 입력 | 선택된 에이전트)
 *  우: 실시간 로그 / 작업 진행 현황 / 작업 트리
 * 넓은 화면(xl)에서는 뷰포트 높이에 맞춰 고정하고, 그보다 좁으면 세로로 쌓아 스크롤한다.
 */
export default function AgentManagementPage() {
  const init = useAgentStore((s) => s.init);
  const centerView = useAgentStore((s) => s.centerView);

  useEffect(() => {
    init();
    // 개발 중 브라우저 콘솔에서 이벤트를 흘려 넣어 볼 수 있게 (프로덕션 빌드에는 안 들어감)
    if (process.env.NODE_ENV === 'development') {
      (window as unknown as { __agentStore?: typeof useAgentStore }).__agentStore = useAgentStore;
    }
  }, [init]);

  return (
    <div className="h-full w-full overflow-y-auto p-3 xl:overflow-hidden">
      <div className="grid min-h-full gap-3 xl:h-full xl:grid-cols-[270px_minmax(0,1fr)_350px] xl:grid-rows-1">
        <div className="flex min-h-0 flex-col gap-3 xl:h-full">
          <div className="min-h-[420px] xl:min-h-0 xl:flex-1 flex flex-col">
            <AgentListPanel />
          </div>
          <StatusSummaryPanel />
        </div>

        <div className="flex min-h-0 min-w-0 flex-col gap-3 xl:h-full">
          <CenterViewTabs />
          {/* Phaser 게임을 매번 다시 만들지 않도록 맵은 숨기기만 하고 결과 화면을 위에 얹는다 */}
          <div className="relative h-[420px] min-w-0 shrink-0 xl:h-auto xl:min-h-0 xl:flex-1">
            <div className={`h-full w-full ${centerView === 'office' ? '' : 'invisible absolute inset-0'}`}>
              <OfficeStage />
            </div>
            {centerView === 'results' && <ResultsPanel />}
            {/* 승인 요청(계획 승인 포함)은 사무실·결과 화면 어디서든 보이게 맨 위에 얹는다 */}
            <PermissionBanner />
          </div>
          <div className="grid shrink-0 gap-3 md:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] xl:h-[296px]">
            <CommandBar />
            <SelectedAgentPanel />
          </div>
        </div>

        <div className="flex min-h-0 flex-col gap-3 xl:h-full">
          <div className="flex h-[300px] flex-col xl:h-auto xl:min-h-0 xl:flex-[1.1]">
            <LogPanel />
          </div>
          <TaskProgressPanel />
          <div className="flex h-[260px] flex-col xl:h-auto xl:min-h-0 xl:flex-1">
            <TaskGraphPanel />
          </div>
        </div>
      </div>
      <AgentEditorDialog />
      <ChoiceDialog />
    </div>
  );
}
