export type AiEditOutcomeState =
  | 'not-requested'
  | 'succeeded'
  | 'unavailable';

export type AiEditAnalysisOutcomes = {
  plan: AiEditOutcomeState;
  subtitle: AiEditOutcomeState;
  silence: AiEditOutcomeState;
  speechReduction: AiEditOutcomeState;
  sfx: AiEditOutcomeState;
};

type AiEditUsagePolicyInput = {
  outcomes: AiEditAnalysisOutcomes;
  isLegacyRequest: boolean;
};

export const shouldReserveAiEditMinutes = ({
  outcomes,
  isLegacyRequest
}: AiEditUsagePolicyInput): boolean => {
  if (isLegacyRequest) {
    return true;
  }

  return Object.values(outcomes).some((state) => state === 'succeeded');
};
