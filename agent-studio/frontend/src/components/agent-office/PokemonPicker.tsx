'use client';

/* eslint-disable @next/next/no-img-element -- 외부(PokeAPI) 스프라이트 */
import { useEffect, useMemo, useState } from 'react';
import { fetchPokemonList, pokemonSpriteUrl, type PokemonEntry } from '@/game/pokemon/fetchSprite';
import { SearchIcon } from '@/components/ui/icons';

interface Props {
  value: number;
  onChange: (entry: PokemonEntry) => void;
  color: string;
}

const PAGE = 120;

/** 전국도감에서 캐릭터를 고르는 그리드. 이름/번호로 검색하고, 스크롤하면 더 보여준다. */
export function PokemonPicker({ value, onChange, color }: Props) {
  const [all, setAll] = useState<PokemonEntry[]>([]);
  const [query, setQuery] = useState('');
  const [limit, setLimit] = useState(PAGE);

  useEffect(() => {
    let alive = true;
    void fetchPokemonList().then((list) => {
      if (alive) setAll(list);
    });
    return () => {
      alive = false;
    };
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return all;
    return all.filter((p) => p.name.includes(q) || String(p.id) === q || String(p.id).startsWith(q));
  }, [all, query]);

  useEffect(() => {
    setLimit(PAGE);
  }, [query]);

  const selected = all.find((p) => p.id === value);

  return (
    <div className="flex min-h-0 flex-col gap-2">
      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <SearchIcon className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="이름(영문) 또는 도감 번호로 검색 — 예: pikachu, 25"
            className="w-full rounded-lg border border-line bg-[#08101f]/80 py-1.5 pl-8 pr-3 text-[12px] text-slate-100 outline-none placeholder:text-slate-600 focus:border-accent/70"
          />
        </div>
        <span className="shrink-0 text-[11px] text-muted">
          {selected ? `#${selected.id} ${selected.name}` : `#${value}`}
        </span>
      </div>

      <div
        className="grid max-h-[220px] min-h-[120px] grid-cols-6 gap-1.5 overflow-y-auto rounded-lg border border-line bg-[#08101f]/60 p-2 sm:grid-cols-8"
        onScroll={(e) => {
          const el = e.currentTarget;
          if (el.scrollHeight - el.scrollTop - el.clientHeight < 120 && limit < filtered.length) setLimit((l) => l + PAGE);
        }}
      >
        {all.length === 0 && <p className="col-span-full py-6 text-center text-[12px] text-slate-500">도감을 불러오는 중...</p>}
        {all.length > 0 && filtered.length === 0 && (
          <p className="col-span-full py-6 text-center text-[12px] text-slate-500">검색 결과가 없습니다.</p>
        )}
        {filtered.slice(0, limit).map((p) => {
          const active = p.id === value;
          return (
            <button
              key={p.id}
              type="button"
              title={`#${p.id} ${p.name}`}
              onClick={() => onChange(p)}
              className={`flex aspect-square items-center justify-center rounded-lg border transition ${
                active ? 'border-transparent' : 'border-transparent hover:border-line-strong hover:bg-white/[0.04]'
              }`}
              style={active ? { background: `${color}33`, boxShadow: `inset 0 0 0 2px ${color}` } : undefined}
            >
              <img src={pokemonSpriteUrl(p.id)} alt={p.name} loading="lazy" className="pixelated h-11 w-11" />
            </button>
          );
        })}
      </div>
    </div>
  );
}
