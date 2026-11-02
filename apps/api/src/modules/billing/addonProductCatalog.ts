/** Append-only product definitions. Never repurpose a sold SKU for a different grant. */
export type AddonProductDefinition = Readonly<{
  id: 'legacy' | 'small' | 'medium' | 'large';
  productId: string;
  postUnits: number;
  aiCaptions: number;
  /** Reference Thailand price only; the native store owns the payable price. */
  priceThb: number;
}>;

export const legacyAddonProductId = 'postdee_post100_caption50';
export const addonCatalogVersion = 3;
export const addonTierProducts: readonly AddonProductDefinition[] = Object.freeze([
  Object.freeze({ id: 'small', productId: 'postdee_post40_caption25', postUnits: 40, aiCaptions: 25, priceThb: 49 } as const),
  Object.freeze({ id: 'medium', productId: 'postdee_post90_caption50', postUnits: 90, aiCaptions: 50, priceThb: 99 } as const),
  Object.freeze({ id: 'large', productId: 'postdee_post190_caption100', postUnits: 190, aiCaptions: 100, priceThb: 199 } as const)
]);

export const readAddonProductDefinition = (
  productId: string,
  configuredLegacyProductId = legacyAddonProductId
): AddonProductDefinition | undefined => {
  // The canonical historical SKU remains verifiable even when a configured
  // legacy alias changes. Both still mean the original 100/50 grant forever.
  if (productId === legacyAddonProductId || productId === configuredLegacyProductId) {
    return { id: 'legacy', productId, postUnits: 100, aiCaptions: 50, priceThb: 49 };
  }
  return addonTierProducts.find(product => product.productId === productId);
};

export const addonGrantSnapshot = (product: AddonProductDefinition) => ({
  postUnitsGranted: product.postUnits,
  aiCaptionsGranted: product.aiCaptions
});
