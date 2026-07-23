export type TranscriptionBenchmarkObservation = {
  provider: string;
  text: string;
  audioDurationSeconds: number;
  elapsedMilliseconds: number;
  usdPerHour: number;
  hallucinatedPhraseCount: number;
  openingSpeechOmitted: boolean;
  timingErrorsMilliseconds: number[];
};

export type TranscriptionComparisonInput = {
  referenceText: string;
  providers: TranscriptionBenchmarkObservation[];
};

export type TranscriptionProviderComparison = TranscriptionBenchmarkObservation & {
  characterErrorRate: number;
  estimatedCostUsd: number;
  medianTimingErrorMilliseconds: number | null;
  p95TimingErrorMilliseconds: number | null;
};

export type TranscriptionComparisonReport = {
  providers: TranscriptionProviderComparison[];
  accuracyWinner: string | 'tie';
  relativeCerImprovementPercent: number;
  accuracyDecisionReason: string;
};

const credentialLikeField = /api.?key|authorization|secret|token/i;

const round = (value: number, digits: number): number => {
  const factor = 10 ** digits;
  return Math.round((value + Number.EPSILON) * factor) / factor;
};

export const normalizeThaiForCer = (value: string): string =>
  value
    .normalize('NFC')
    .toLocaleLowerCase('th')
    .replace(/[\p{P}\p{S}\s]/gu, '');

const levenshteinDistance = (reference: string, hypothesis: string): number => {
  const hypothesisCharacters = Array.from(hypothesis);
  let previous = Array.from(
    { length: hypothesisCharacters.length + 1 },
    (_, index) => index
  );

  Array.from(reference).forEach((referenceCharacter, referenceIndex) => {
    const current = [referenceIndex + 1];

    hypothesisCharacters.forEach((hypothesisCharacter, hypothesisIndex) => {
      const insertion = current[hypothesisIndex]! + 1;
      const deletion = previous[hypothesisIndex + 1]! + 1;
      const substitution =
        previous[hypothesisIndex]! +
        (referenceCharacter === hypothesisCharacter ? 0 : 1);
      current.push(Math.min(insertion, deletion, substitution));
    });

    previous = current;
  });

  return previous[hypothesisCharacters.length] ?? 0;
};

const sortedTimingErrors = (values: number[]): number[] =>
  values
    .filter((value) => Number.isFinite(value) && value >= 0)
    .slice()
    .sort((left, right) => left - right);

const median = (values: number[]): number | null => {
  if (values.length === 0) return null;
  const middle = Math.floor(values.length / 2);
  if (values.length % 2 === 1) return values[middle] ?? null;
  return ((values[middle - 1] ?? 0) + (values[middle] ?? 0)) / 2;
};

const nearestRankP95 = (values: number[]): number | null => {
  if (values.length === 0) return null;
  return values[Math.max(0, Math.ceil(values.length * 0.95) - 1)] ?? null;
};

const assertFiniteNonNegative = (value: number, label: string): void => {
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${label} must be a finite non-negative number`);
  }
};

export const validateSanitizedBenchmarkValue = (
  value: unknown,
  path = 'benchmark'
): void => {
  if (Array.isArray(value)) {
    value.forEach((entry, index) =>
      validateSanitizedBenchmarkValue(entry, `${path}[${index}]`)
    );
    return;
  }

  if (typeof value !== 'object' || value === null) return;

  for (const [key, nestedValue] of Object.entries(value)) {
    if (credentialLikeField.test(key)) {
      throw new Error(`Credential-like field is not allowed: ${path}.${key}`);
    }
    validateSanitizedBenchmarkValue(nestedValue, `${path}.${key}`);
  }
};

export const buildTranscriptionComparison = (
  input: TranscriptionComparisonInput
): TranscriptionComparisonReport => {
  validateSanitizedBenchmarkValue(input);
  const normalizedReference = normalizeThaiForCer(input.referenceText);
  const referenceCharacters = Array.from(normalizedReference);

  if (referenceCharacters.length === 0) {
    throw new Error('referenceText must contain visible letters or numbers');
  }
  if (input.providers.length < 2) {
    throw new Error('At least two provider observations are required');
  }

  const providers = input.providers.map((provider) => {
    assertFiniteNonNegative(
      provider.audioDurationSeconds,
      `${provider.provider}.audioDurationSeconds`
    );
    assertFiniteNonNegative(
      provider.elapsedMilliseconds,
      `${provider.provider}.elapsedMilliseconds`
    );
    assertFiniteNonNegative(provider.usdPerHour, `${provider.provider}.usdPerHour`);
    assertFiniteNonNegative(
      provider.hallucinatedPhraseCount,
      `${provider.provider}.hallucinatedPhraseCount`
    );

    const normalizedHypothesis = normalizeThaiForCer(provider.text);
    const timingErrors = sortedTimingErrors(provider.timingErrorsMilliseconds);
    const characterErrorRate = round(
      levenshteinDistance(normalizedReference, normalizedHypothesis) /
        referenceCharacters.length,
      6
    );

    return {
      ...provider,
      characterErrorRate,
      estimatedCostUsd: round(
        (provider.usdPerHour * provider.audioDurationSeconds) / 3600,
        6
      ),
      medianTimingErrorMilliseconds: median(timingErrors),
      p95TimingErrorMilliseconds: nearestRankP95(timingErrors)
    };
  });

  const rankedByCer = providers
    .slice()
    .sort(
      (left, right) => left.characterErrorRate - right.characterErrorRate
    );
  const lowerCer = rankedByCer[0]!;
  const higherCer = rankedByCer[rankedByCer.length - 1]!;
  const absoluteCerDifference =
    higherCer.characterErrorRate - lowerCer.characterErrorRate;
  const relativeCerImprovementPercent =
    higherCer.characterErrorRate === 0
      ? 0
      : round(
          (absoluteCerDifference / higherCer.characterErrorRate) * 100,
          2
        );
  const accuracyIsTied = absoluteCerDifference < 0.03;
  const accuracyImprovedEnough = relativeCerImprovementPercent >= 20;
  const hallucinationsDidNotIncrease =
    lowerCer.hallucinatedPhraseCount <= higherCer.hallucinatedPhraseCount;
  const accuracyWinner =
    !accuracyIsTied &&
    accuracyImprovedEnough &&
    hallucinationsDidNotIncrease
      ? lowerCer.provider
      : 'tie';
  const accuracyDecisionReason = accuracyIsTied
    ? 'Absolute CER differs by less than three percentage points'
    : !accuracyImprovedEnough
      ? 'Relative CER improvement is below twenty percent'
      : !hallucinationsDidNotIncrease
        ? 'The lower-CER provider increased hallucinated phrases'
        : `${lowerCer.provider} lowers relative CER by ${relativeCerImprovementPercent}% without increasing hallucinations`;

  return {
    providers,
    accuracyWinner,
    relativeCerImprovementPercent,
    accuracyDecisionReason
  };
};
