CREATE TABLE "LinkInBioProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "storeName" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "links" JSONB NOT NULL,
    "isPublished" BOOLEAN NOT NULL DEFAULT false,
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "LinkInBioProfile_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "LinkInBioProfile_userId_key" ON "LinkInBioProfile"("userId");
CREATE UNIQUE INDEX "LinkInBioProfile_slug_key" ON "LinkInBioProfile"("slug");
ALTER TABLE "LinkInBioProfile" ADD CONSTRAINT "LinkInBioProfile_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
