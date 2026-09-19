export function AppFooter() {
  return (
    <footer className="flex h-9 shrink-0 items-center gap-3 border-t border-line bg-[#0a1428]/90 px-4 text-[11px] text-muted md:px-5">
      <span className="font-semibold text-slate-300">AI Agent Office Simulator</span>
      <span className="text-line-strong">|</span>
      <span>Powered by Next.js + Phaser.js</span>
      <span className="hidden text-line-strong sm:inline">|</span>
      <span className="hidden sm:inline">당신의 아이디어가 현실이 되는 순간, AI 에이전트들이 함께합니다.</span>
      <span className="ml-auto hidden md:inline">모든 에이전트가 목표를 향해 달리고 있습니다.</span>
    </footer>
  );
}
