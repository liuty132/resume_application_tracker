import * as cheerio from 'cheerio';

export interface ExtractionResult {
  companyName?: string;
  jobTitle?: string;
}

export function extractJobMetadata(html: string, url: string): ExtractionResult {
  const $ = cheerio.load(html);
  let result: ExtractionResult = {};

  // Tier 1: Domain-specific selectors
  const hostname = new URL(url).hostname || '';

  if (hostname.includes('linkedin.com')) {
    result = extractFromLinkedIn($);
  } else if (hostname.includes('greenhouse.io')) {
    result = extractFromGreenhouse($);
  } else if (hostname.includes('lever.co')) {
    result = extractFromLever($);
  } else if (hostname.includes('workday.com')) {
    result = extractFromWorkday($);
  }

  // Tier 2: Fallback to Open Graph tags
  if (!result.jobTitle || !result.companyName) {
    const ogTitle = $('meta[property="og:title"]').attr('content');
    if (ogTitle) {
      const parsed = parseOGTitle(ogTitle);
      if (!result.jobTitle && parsed.jobTitle) result.jobTitle = parsed.jobTitle;
      if (!result.companyName && parsed.companyName) result.companyName = parsed.companyName;
    }
  }

  // Tier 3: Fallback to <title> tag
  if (!result.jobTitle) {
    const titleText = $('title').text().trim();
    if (titleText && titleText.length > 0) {
      result.jobTitle = titleText.split('|')[0].split(' - ')[0].trim();
    }
  }

  return result;
}

function extractFromLinkedIn($: ReturnType<typeof cheerio.load>): ExtractionResult {
  // LinkedIn job posting selectors (may vary)
  const jobTitle = $('h1[class*="title"]').first().text().trim();
  const companyName = $('a[class*="company"]').first().text().trim();
  return { jobTitle: jobTitle || undefined, companyName: companyName || undefined };
}

function extractFromGreenhouse($: ReturnType<typeof cheerio.load>): ExtractionResult {
  const jobTitle = $('[data-qa="job-title"]').text().trim() || $('h1').first().text().trim();
  const companyName = $('[data-qa="company-name"]').text().trim() ||
    $('a[class*="company"]').text().trim();
  return { jobTitle: jobTitle || undefined, companyName: companyName || undefined };
}

function extractFromLever($: ReturnType<typeof cheerio.load>): ExtractionResult {
  const jobTitle = $('h1').first().text().trim();
  const companyName = $('[data-qa="posting-team-name"]').text().trim() ||
    $('[class*="company"]').first().text().trim();
  return { jobTitle: jobTitle || undefined, companyName: companyName || undefined };
}

function extractFromWorkday($: ReturnType<typeof cheerio.load>): ExtractionResult {
  const jobTitle = $('[class*="job-title"]').first().text().trim() ||
    $('h1').first().text().trim();
  const companyName = $('[class*="company-name"]').first().text().trim() ||
    $('[class*="org"]').first().text().trim();
  return { jobTitle: jobTitle || undefined, companyName: companyName || undefined };
}

function parseOGTitle(ogTitle: string): ExtractionResult {
  // Try to parse patterns like:
  // "Job Title at Company Name"
  // "Job Title | Company Name"
  const atMatch = ogTitle.match(/^(.+?)\s+at\s+(.+?)$/i);
  if (atMatch) {
    return { jobTitle: atMatch[1].trim(), companyName: atMatch[2].trim() };
  }

  const pipeMatch = ogTitle.match(/^(.+?)\s*\|\s*(.+?)$/);
  if (pipeMatch) {
    return { jobTitle: pipeMatch[1].trim(), companyName: pipeMatch[2].trim() };
  }

  return { jobTitle: ogTitle.trim() };
}
