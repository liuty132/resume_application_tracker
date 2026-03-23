import { pgTable, uuid, varchar, text, timestamp } from 'drizzle-orm/pg-core';
import { relations } from 'drizzle-orm';

export const jobs = pgTable('jobs', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: varchar('user_id', { length: 128 }).notNull(),
  url: text('url').notNull(),
  companyName: varchar('company_name', { length: 256 }),
  jobTitle: varchar('job_title', { length: 256 }),
  s3Key: varchar('s3_key', { length: 512 }).notNull(),
  appliedAt: timestamp('applied_at').defaultNow().notNull(),
  status: varchar('status', { length: 32 }).default('applied'),
});

export type Job = typeof jobs.$inferSelect;
export type NewJob = typeof jobs.$inferInsert;
