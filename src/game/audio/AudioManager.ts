import { AUDIO_CONFIG, type SoundEffectId } from '../config/audioConfig';
import type { GameSettings } from '../state/GameState';

type AudioBufferKey = 'music' | SoundEffectId;

const getAudioPaths = (): Array<[AudioBufferKey, string]> => [
  ['music', AUDIO_CONFIG.paths.music],
  ...(Object.entries(AUDIO_CONFIG.paths.sfx) as Array<[SoundEffectId, string]>),
];

export class AudioManager {
  private context: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private musicGain: GainNode | null = null;
  private sfxGain: GainNode | null = null;
  private musicSource: AudioBufferSourceNode | null = null;
  private readonly encoded = new Map<AudioBufferKey, ArrayBuffer>();
  private readonly buffers = new Map<AudioBufferKey, AudioBuffer>();
  private settings: GameSettings;

  public constructor(settings: GameSettings) {
    this.settings = { ...settings };
  }

  public async prepare(): Promise<string[]> {
    const failures: string[] = [];
    const results = await Promise.allSettled(
      getAudioPaths().map(async ([key, path]) => {
        const response = await fetch(path);
        if (!response.ok) throw new Error(`${path}: ${response.status}`);
        this.encoded.set(key, await response.arrayBuffer());
      }),
    );
    for (const result of results) {
      if (result.status === 'rejected') {
        failures.push(
          result.reason instanceof Error ? result.reason.message : String(result.reason),
        );
      }
    }
    return failures;
  }

  public async unlock(): Promise<void> {
    if (!this.context) {
      this.context = new AudioContext();
      this.masterGain = this.context.createGain();
      this.musicGain = this.context.createGain();
      this.sfxGain = this.context.createGain();
      this.musicGain.connect(this.masterGain);
      this.sfxGain.connect(this.masterGain);
      this.masterGain.connect(this.context.destination);
      this.applySettings(this.settings);
      await Promise.all(
        [...this.encoded.entries()].map(async ([key, encoded]) => {
          try {
            this.buffers.set(key, await this.context!.decodeAudioData(encoded.slice(0)));
          } catch {
            // A missing or malformed sound must never block gameplay.
          }
        }),
      );
    }
    if (this.context.state === 'suspended') await this.context.resume();
  }

  public applySettings(settings: GameSettings): void {
    this.settings = { ...settings };
    if (!this.context || !this.masterGain || !this.musicGain || !this.sfxGain) return;
    const now = this.context.currentTime;
    this.masterGain.gain.setTargetAtTime(settings.masterMuted ? 0 : 1, now, 0.02);
    this.musicGain.gain.setTargetAtTime(settings.musicVolume, now, 0.02);
    this.sfxGain.gain.setTargetAtTime(settings.sfxVolume, now, 0.02);
  }

  public startMusic(): void {
    if (!this.context || !this.musicGain || this.musicSource) return;
    const buffer = this.buffers.get('music');
    if (!buffer) return;
    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.loop = true;
    source.connect(this.musicGain);
    source.start();
    source.addEventListener('ended', () => {
      if (this.musicSource === source) this.musicSource = null;
    });
    this.musicSource = source;
  }

  public stopMusic(): void {
    if (!this.musicSource) return;
    try {
      this.musicSource.stop();
    } catch {
      // Already stopped.
    }
    this.musicSource.disconnect();
    this.musicSource = null;
  }

  public play(id: SoundEffectId): void {
    if (!this.context || !this.sfxGain || this.settings.masterMuted) return;
    const buffer = this.buffers.get(id);
    if (!buffer) return;
    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(this.sfxGain);
    source.start();
    source.addEventListener('ended', () => source.disconnect(), { once: true });
  }

  public async pause(): Promise<void> {
    if (this.context?.state === 'running') await this.context.suspend();
  }

  public async resume(): Promise<void> {
    if (this.context?.state === 'suspended') await this.context.resume();
  }

  public destroy(): void {
    this.stopMusic();
    void this.context?.close();
    this.context = null;
  }
}
