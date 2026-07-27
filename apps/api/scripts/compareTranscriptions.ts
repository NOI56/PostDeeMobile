import { readFile } from 'node:fs/promises';

import {
  buildTranscriptionComparison,
  type TranscriptionBenchmarkObservation,
  validateSanitizedBenchmarkValue
} from '../src/modules/aiEdits/transcriptionComparison.js';

const readRequiredArgument = (name: string): string => {
  const index = process.argv.indexOf(name);
  const value = index >= 0 ? process.argv[index + 1] : undefined;
  if (!value || value.startsWith('--')) {
    throw new Error(`Missing required argument: ${name}`);
  }
  return value;
};

const readJson = async (path: string): Promise<unknown> =>
  JSON.parse(await readFile(path, 'utf8')) as unknown;

const readReferenceText = (value: unknown): string => {
  if (
    typeof value !== 'object' ||
    value === null ||
    typeof (value as { referenceText?: unknown }).referenceText !== 'string'
  ) {
    throw new Error('Reference JSON must contain a referenceText string');
  }
  return (value as { referenceText: string }).referenceText;
};

const readProviderObservation = (
  value: unknown,
  label: string
): TranscriptionBenchmarkObservation => {
  validateSanitizedBenchmarkValue(value, label);
  if (typeof value !== 'object' || value === null) {
    throw new Error(`${label} JSON must contain an object`);
  }

  const observation = value as Partial<TranscriptionBenchmarkObservation>;
  if (
    typeof observation.provider !== 'string' ||
    typeof observation.text !== 'string' ||
    typeof observation.audioDurationSeconds !== 'number' ||
    typeof observation.elapsedMilliseconds !== 'number' ||
    typeof observation.usdPerHour !== 'number' ||
    typeof observation.hallucinatedPhraseCount !== 'number' ||
    typeof observation.openingSpeechOmitted !== 'boolean' ||
    !Array.isArray(observation.timingErrorsMilliseconds) ||
    !observation.timingErrorsMilliseconds.every(
      (entry) => typeof entry === 'number'
    )
  ) {
    throw new Error(`${label} JSON has an invalid benchmark observation`);
  }

  return observation as TranscriptionBenchmarkObservation;
};

const referencePath = readRequiredArgument('--reference');
const groqPath = readRequiredArgument('--groq');
const elevenLabsPath = readRequiredArgument('--elevenlabs');

const [referenceValue, groqValue, elevenLabsValue] = await Promise.all([
  readJson(referencePath),
  readJson(groqPath),
  readJson(elevenLabsPath)
]);
validateSanitizedBenchmarkValue(referenceValue, 'reference');

const report = buildTranscriptionComparison({
  referenceText: readReferenceText(referenceValue),
  providers: [
    readProviderObservation(groqValue, 'groq'),
    readProviderObservation(elevenLabsValue, 'elevenlabs')
  ]
});

process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
