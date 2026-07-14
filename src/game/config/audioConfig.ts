export const AUDIO_CONFIG = {
  musicVolume: 0.38,
  sfxVolume: 0.72,
  fadeMs: 180,
  paths: {
    music: '/assets/audio/music/pocket-vector-drive.wav',
    sfx: {
      uiSelect: '/assets/audio/sfx/ui-select.wav',
      countdown: '/assets/audio/sfx/countdown.wav',
      snap: '/assets/audio/sfx/snap.wav',
      throw: '/assets/audio/sfx/throw.wav',
      flight: '/assets/audio/sfx/flight.wav',
      catch: '/assets/audio/sfx/catch.wav',
      deep: '/assets/audio/sfx/deep-completion.wav',
      touchdown: '/assets/audio/sfx/touchdown.wav',
      bonus: '/assets/audio/sfx/bonus-active.wav',
      multiplier: '/assets/audio/sfx/multiplier.wav',
      incomplete: '/assets/audio/sfx/incomplete.wav',
      interception: '/assets/audio/sfx/interception.wav',
      meterLoss: '/assets/audio/sfx/meter-loss.wav',
      timerWarning: '/assets/audio/sfx/timer-warning.wav',
      gameOver: '/assets/audio/sfx/game-over.wav',
      continueSuccess: '/assets/audio/sfx/continue-success.wav',
    },
  },
} as const;

export type SoundEffectId = keyof typeof AUDIO_CONFIG.paths.sfx;
