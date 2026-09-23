import { AppHeader } from '@/components/layout/AppHeader';
import { AppFooter } from '@/components/layout/AppFooter';
import { AccessGate } from '@/components/layout/AccessGate';

/** 시안처럼 상단 헤더 + 하단 푸터 사이에 화면을 꽉 채우는 관리자 셸 */
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <AccessGate>
      <div className="flex h-dvh w-full flex-col bg-background text-slate-100">
        <AppHeader />
        <main className="min-h-0 min-w-0 flex-1 overflow-hidden">{children}</main>
        <AppFooter />
      </div>
    </AccessGate>
  );
}
