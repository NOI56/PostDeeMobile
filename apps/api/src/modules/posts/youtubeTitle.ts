export const youtubeTitleMaxLength = 100;

export const isValidYoutubeTitle = (title: string) =>
  !/[<>]/.test(title) && [...title].length <= youtubeTitleMaxLength;

export const deriveYoutubeTitle = (caption?: string) => {
  const firstLine = caption?.replace(/[<>]/g, '').trim().split(/[\r\n]+/)
    .find((line) => line.trim().length > 0)?.replace(/\s+/g, ' ').trim() ?? '';
  const sentenceEnd = /[.!?。！？](?:\s|$)/.exec(firstLine);
  const firstSentence = sentenceEnd ? firstLine.slice(0, sentenceEnd.index + 1) : firstLine;
  return [...firstSentence].slice(0, youtubeTitleMaxLength).join('').trim() || 'PostDee video';
};
