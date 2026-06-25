import { PrismaClient } from '@prisma/client';

import { createPrismaUserRepository } from '../src/modules/users/prismaUserRepository.js';
import { seedMockUser } from '../src/modules/users/userSeedService.js';

const prisma = new PrismaClient();

try {
  const user = await seedMockUser({
    userStore: createPrismaUserRepository({ prisma })
  });

  console.log(`Seeded PostDee user: ${user.id} (${user.email})`);
} finally {
  await prisma.$disconnect();
}
