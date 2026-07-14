import type { PointerSample, ThrowGesture } from './gestureMath';
import { calculateThrowGesture } from './gestureMath';

export class PointerSampler {
  private activePointerId: number | null = null;
  private samples: PointerSample[] = [];

  public get isActive(): boolean {
    return this.activePointerId !== null;
  }

  public owns(pointerId: number): boolean {
    return this.activePointerId === pointerId;
  }

  public start(pointerId: number, sample: PointerSample): boolean {
    if (this.activePointerId !== null) return false;
    this.activePointerId = pointerId;
    this.samples = [sample];
    return true;
  }

  public add(pointerId: number, sample: PointerSample): void {
    if (this.activePointerId !== pointerId) return;
    const previous = this.samples[this.samples.length - 1];
    if (previous && sample.timestampMs < previous.timestampMs) return;
    this.samples.push(sample);
    // Preserve the original pointer-down for direction and destination while
    // rolling only the intermediate history used for recent release velocity.
    if (this.samples.length > 24) this.samples.splice(1, 1);
  }

  public addMany(pointerId: number, samples: readonly PointerSample[]): void {
    for (const sample of samples) this.add(pointerId, sample);
  }

  public finish(pointerId: number, sample?: PointerSample): ThrowGesture | null {
    if (this.activePointerId !== pointerId) return null;
    if (sample) this.add(pointerId, sample);
    const gesture = calculateThrowGesture(this.samples);
    this.reset();
    return gesture;
  }

  public cancel(pointerId?: number): void {
    if (pointerId === undefined || this.activePointerId === pointerId) this.reset();
  }

  public getSamples(): readonly PointerSample[] {
    return this.samples;
  }

  private reset(): void {
    this.activePointerId = null;
    this.samples = [];
  }
}
