'use client';

import { useEffect, useRef } from 'react';
import type { Game } from 'phaser';
import { createGame } from '@/game/createGame';

/**
 * 이 파일은 페이지에서 next/dynamic(ssr:false)로만 불러온다 (Phaser는 브라우저 전용).
 * 여기서 다시 동적 import를 중첩하면 별도 청크로 쪼개지면서 zustand 스토어 모듈이
 * 두 벌로 로드되는 문제가 있었어서, createGame은 일반 정적 import로 가져온다.
 */
export function OfficeCanvas() {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const gameRef = useRef<Game | null>(null);

  useEffect(() => {
    if (!hostRef.current) return;
    const game = createGame(hostRef.current);
    gameRef.current = game;
    if (process.env.NODE_ENV === 'development') {
      (window as unknown as { __phaserGame?: Game }).__phaserGame = game;
    }

    // flex 레이아웃이 자리잡기 전에 Phaser가 먼저 크기를 재는 경우가 있어,
    // 컨테이너 크기가 바뀔 때마다(초기 레이아웃 포함) 다시 맞춘다.
    const resizeObserver = new ResizeObserver(() => game.scale.refresh());
    resizeObserver.observe(hostRef.current);

    return () => {
      resizeObserver.disconnect();
      game.destroy(true);
      gameRef.current = null;
    };
  }, []);

  return <div ref={hostRef} className="flex h-full w-full items-center justify-center overflow-hidden bg-[#08101f]" />;
}
