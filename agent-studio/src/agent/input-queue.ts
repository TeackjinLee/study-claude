/**
 * query()에 스트리밍 입력으로 넘기는 비동기 큐.
 * 첫 명령을 넣고 시작한 뒤, 실행 도중 사용자가 보낸 추가 지시를 push로 끼워 넣는다. close() 하면 입력이 끝나 세션이 닫힌다.
 */
export class InputQueue<T> implements AsyncIterable<T> {
  private readonly items: T[] = [];
  private waiter: ((r: IteratorResult<T>) => void) | null = null;
  private closed = false;

  get isClosed() {
    return this.closed;
  }

  /** 닫힌 뒤에는 넣지 않고 false */
  push(item: T): boolean {
    if (this.closed) return false;
    if (this.waiter) {
      const w = this.waiter;
      this.waiter = null;
      w({ value: item, done: false });
    } else {
      this.items.push(item);
    }
    return true;
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    if (this.waiter) {
      const w = this.waiter;
      this.waiter = null;
      w({ value: undefined, done: true });
    }
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: () => {
        if (this.items.length > 0) return Promise.resolve({ value: this.items.shift() as T, done: false });
        if (this.closed) return Promise.resolve({ value: undefined, done: true });
        return new Promise((resolve) => (this.waiter = resolve));
      },
      return: () => {
        this.close();
        return Promise.resolve({ value: undefined, done: true });
      },
    };
  }
}

/**
 * 실행 도중 추가 지시를 받을 때 "언제 실행이 끝났다고 볼지" 정한다.
 * - 추가 지시가 없었으면 첫 결과(result)에서 바로 끝.
 * - 추가 지시가 있었으면 그 지시가 이번 턴에 합쳐졌을 수도, 다음 턴으로 이어질 수도 있다.
 *   결과 뒤에 새 턴의 활동이 오면 다음 결과를 기다리고, 조용하면(idleMs) 또는 세션이 idle을 알리면 끝낸다.
 */
export class RunCompletion {
  private sinceResult = 0;
  private waitingAfterResult = false;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private done = false;

  constructor(
    private readonly onFinish: () => void,
    private readonly idleMs = 5000,
  ) {}

  get finished() {
    return this.done;
  }

  /** 결과를 기다리는 동안 추가 지시를 보냄 */
  followUp() {
    if (this.done) return false;
    this.sinceResult++;
    this.clearTimer();
    this.waitingAfterResult = false;
    return true;
  }

  result() {
    if (this.done) return;
    if (this.sinceResult === 0) return this.finish();
    this.sinceResult = 0;
    this.waitingAfterResult = true;
    this.clearTimer();
    this.timer = setTimeout(() => this.finish(), this.idleMs);
  }

  /** 결과 뒤에 모델의 새 활동이 옴 = 추가 지시가 다음 턴으로 이어졌다. 다음 결과를 기다린다 */
  activity() {
    if (!this.waitingAfterResult) return;
    this.waitingAfterResult = false;
    this.clearTimer();
  }

  /** 세션이 idle을 알림 */
  idle() {
    if (this.waitingAfterResult) this.finish();
  }

  finish() {
    if (this.done) return;
    this.done = true;
    this.clearTimer();
    this.onFinish();
  }

  private clearTimer() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }
}
