/**
 * PokeAPI 스프라이트 URL. /pokemon/{id}의 sprites.front_default가 가리키는 주소와 같아서
 * API를 한 번 더 부르지 않고 바로 만든다 (사용자가 캐릭터를 고를 때 수백 장을 보여줘야 하므로).
 */
export function pokemonSpriteUrl(id: number): string {
  return `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${id}.png`;
}

export interface PokemonEntry {
  id: number;
  name: string;
}

let listCache: Promise<PokemonEntry[]> | null = null;

/** 전국도감 목록 (이름/번호). 캐릭터 선택 화면의 검색용. 실패하면 1~151번만 번호로 채운다. */
export function fetchPokemonList(): Promise<PokemonEntry[]> {
  if (!listCache) {
    listCache = fetch('https://pokeapi.co/api/v2/pokemon?limit=1025')
      .then(async (res) => {
        if (!res.ok) throw new Error(String(res.status));
        const data = (await res.json()) as { results: { name: string; url: string }[] };
        return data.results
          .map((r) => ({ id: Number(r.url.match(/\/(\d+)\/?$/)?.[1] ?? 0), name: r.name }))
          .filter((p) => p.id > 0);
      })
      .catch(() => Array.from({ length: 151 }, (_, i) => ({ id: i + 1, name: `#${i + 1}` })));
  }
  return listCache;
}
