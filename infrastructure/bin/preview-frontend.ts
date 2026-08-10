#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { PreviewFrontendStack } from '../lib/stacks/PreviewFrontendStack';

const sourceSha = process.env.IVANRY_PREVIEW_SHA;
if (!sourceSha || !/^[a-f0-9]{40,64}$/.test(sourceSha)) {
  throw new Error('IVANRY_PREVIEW_SHA must be a full lowercase Git SHA.');
}
const approvedAccount = '473968112686';
const approvedRegion = 'us-east-1';
const approvedCoreApiUrl = 'https://y2a0146ujh.execute-api.us-east-1.amazonaws.com/v1';
const approvedConnectorApiUrl = 'https://mcp.ivanry.com';
if (process.env.CDK_ACCOUNT && process.env.CDK_ACCOUNT !== approvedAccount) {
  throw new Error('Preview CDK account does not match the approved Ivanry account.');
}
if (process.env.CDK_REGION && process.env.CDK_REGION !== approvedRegion) {
  throw new Error('Preview CDK region does not match the approved Ivanry region.');
}
if (process.env.IVANRY_PREVIEW_CORE_API_URL && process.env.IVANRY_PREVIEW_CORE_API_URL !== approvedCoreApiUrl) {
  throw new Error('Preview core API does not match the approved read-only dependency.');
}

const app = new cdk.App();
new PreviewFrontendStack(app, 'PortfolioPreviewFrontendStack', {
  env: {
    account: approvedAccount,
    region: approvedRegion,
  },
  sourceSha,
  coreApiUrl: approvedCoreApiUrl,
  connectorApiUrl: approvedConnectorApiUrl,
});
app.synth();
