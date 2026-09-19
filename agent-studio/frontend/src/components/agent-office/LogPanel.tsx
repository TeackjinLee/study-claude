'use client';

import { useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { ActivityIcon } from '@/components/ui/icons';
import { LogFilterSelect, LogList, type LogFilter } from './LogList';

export function LogPanel() {
  const connection = useAgentStore((s) => s.connection);
  const [filter, setFilter] = useState<LogFilter>('all');

  return (
    <section className="panel flex min-h-0 flex-1 flex-col overflow-hidden">
      <div className="panel-header">
        <h2 className="panel-title">
          <ActivityIcon className="h-4 w-4 text-blue-300" />
          실시간 로그
          <span
            className={`ml-1 inline-block h-1.5 w-1.5 rounded-full ${connection === 'connected' ? 'bg-emerald-400 pulse-dot' : 'bg-slate-500'}`}
            title={connection}
          />
        </h2>
        <LogFilterSelect value={filter} onChange={setFilter} />
      </div>

      <LogList filter={filter} />
    </section>
  );
}
