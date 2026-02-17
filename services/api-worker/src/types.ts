// services/api-worker/src/types.ts

export type Emotion = "calm" | "warm" | "confident" | "friendly" | "neutral";

export type Suggestion = {
  label: string;
  text: string;
  why_it_works: string;
  emotion_preview: Emotion[];
};
