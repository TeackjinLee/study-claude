'use client';

/* eslint-disable @next/next/no-img-element -- 외부(PokeAPI) 스프라이트라 next/image 최적화 대상이 아니다 */
import { useState } from 'react';
import type { AgentDef, AgentRole } from '@/types/agent';
import { useAgentStore } from '@/store/agentStore';
import { pokemonSpriteUrl } from '@/game/pokemon/fetchSprite';

interface Props {
  /** 스토어에 등록된 에이전트 id. 편집 중인 정의를 미리 보여줄 땐 def를 직접 넘긴다 */
  role?: AgentRole;
  def?: Pick<AgentDef, 'name' | 'shortName' | 'color' | 'pokemonId'>;
  /** px 단위 정사각형 크기 */
  size?: number;
  className?: string;
}

/** 에이전트 색 배경 위에 포켓몬 스프라이트를 올린 썸네일. 이미지를 못 받으면 이니셜을 보여준다. */
export function AgentAvatar({ role, def, size = 48, className = '' }: Props) {
  const fromStore = useAgentStore((s) => (role ? s.defsById[role] : undefined));
  const meta = def ?? fromStore;
  const [failed, setFailed] = useState(false);
  const radius = size >= 40 ? 12 : 8;

  if (!meta) {
    return <div className={`shrink-0 rounded-lg bg-white/5 ${className}`} style={{ width: size, height: size }} />;
  }

  return (
    <div
      className={`relative flex shrink-0 items-center justify-center overflow-hidden ${className}`}
      style={{
        width: size,
        height: size,
        borderRadius: radius,
        background: `radial-gradient(circle at 50% 35%, ${meta.color}55 0%, ${meta.color}22 55%, #0b1224 100%)`,
        boxShadow: `inset 0 0 0 1px ${meta.color}66`,
      }}
    >
      {!failed ? (
        <img
          key={meta.pokemonId}
          src={pokemonSpriteUrl(meta.pokemonId)}
          alt={meta.name}
          loading="lazy"
          onError={() => setFailed(true)}
          className="pixelated"
          style={{ width: size * 1.15, height: size * 1.15, marginTop: size * 0.05 }}
        />
      ) : (
        <span className="text-xs font-bold" style={{ color: meta.color }}>
          {meta.shortName.slice(0, 2)}
        </span>
      )}
    </div>
  );
}
