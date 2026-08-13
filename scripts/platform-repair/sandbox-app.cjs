#!/usr/bin/env node
'use strict';

const path = require('node:path');

const root = path.resolve(process.env.LOOP_PROJECT_ROOT ?? '');
if (!root || root === path.parse(root).root) throw new Error('LOOP_PROJECT_ROOT must identify the repair worktree.');
require(path.join(root, 'node_modules', 'ts-node', 'register', 'transpile-only'));

const cdk = require(path.join(root, 'node_modules', 'aws-cdk-lib'));
const stacks = path.join(root, 'infrastructure', 'lib', 'stacks');
const { BrokerSyncDataStack } = require(path.join(stacks, 'BrokerSyncDataStack.ts'));
const { CorporateEventsDataStack } = require(path.join(stacks, 'CorporateEventsDataStack.ts'));
const { PortfolioLegalDataStack } = require(path.join(stacks, 'PortfolioLegalDataStack.ts'));
const { PortfolioMarketDataApiStack } = require(path.join(stacks, 'PortfolioMarketDataApiStack.ts'));
const { PortfolioMarketDataDataStack } = require(path.join(stacks, 'PortfolioMarketDataDataStack.ts'));
const { PortfolioMgmtStack } = require(path.join(stacks, 'PortfolioMgmtStack.ts'));
const { PortfolioQuickInsightsRuntimeStack } = require(path.join(stacks, 'PortfolioQuickInsightsRuntimeStack.ts'));
const { PortfolioTaxPlanningDataStack } = require(path.join(stacks, 'PortfolioTaxPlanningDataStack.ts'));
const { SecurityBaselineStack } = require(path.join(stacks, 'SecurityBaselineStack.ts'));

const account = '109837541383';
const region = 'us-east-1';
const host = 'preview.ivanry.com';
const certificateArn = process.env.SANDBOX_CERTIFICATE_ARN;
if (!new RegExp(`^arn:aws:acm:${region}:${account}:certificate/[a-f0-9-]+$`).test(certificateArn ?? '')) throw new Error('A Sandbox-owned preview certificate ARN is required.');
if ((process.env.CDK_ACCOUNT ?? process.env.CDK_DEFAULT_ACCOUNT) !== account) throw new Error('CDK_ACCOUNT must be the IVANRY Sandbox account.');
if ((process.env.CDK_REGION ?? process.env.CDK_DEFAULT_REGION) !== region) throw new Error('CDK_REGION must be us-east-1.');

const app = new cdk.App();
app.node.setContext('ivanryEnvironment', 'sandbox');
app.node.setContext('ivanryWebHost', host);
app.node.setContext('ivanryCertificateArn', certificateArn);
app.node.setContext('enableGoogleAuth', false);
app.node.setContext('ivanrySelfSignUpEnabled', false);
app.node.setContext('ivanryScheduledJobsEnabled', false);
app.node.setContext('ivanryBrokerSyncEnabled', false);
// The runtime is an already deployed, separately retained Sandbox stack. Core
// may invoke that exact runtime, but it must not gain direct Bedrock model
// authority as part of this narrowly scoped delivery lane.
app.node.setContext('ivanryBedrockEnabled', false);
app.node.setContext('ivanryQuickInsightsEnabled', true);
app.node.setContext('ivanryBillingEnabled', false);
app.node.setContext('twelveDataSecretArn', '');
app.node.setContext('twelveDataEnabled', false);
app.node.setContext('marketDataArchiveManifestsEnabled', false);
app.node.setContext('marketDataRawArchiveEnabled', false);
app.node.setContext('marketDataVerificationEnabled', false);
app.node.setContext('marketDataIndicatorVerificationEnabled', false);
app.node.setContext('twelveDataShadowCompareEnabled', false);
const env = { account, region };

const security = new SecurityBaselineStack(app, 'IvanrySandboxSecurityBaselineStack', { env, description: 'Ivanry Sandbox encryption, audit, consent, and deletion baseline' });
const marketData = new PortfolioMarketDataDataStack(app, 'IvanrySandboxMarketDataDataStack', { env, description: 'Ivanry Sandbox market-data cache and permitted archive storage' });
marketData.addDependency(security);
const marketDataApi = new PortfolioMarketDataApiStack(app, 'IvanrySandboxMarketDataApiStack', {
  env, description: 'Ivanry Sandbox market-data API runtime without production credentials',
  marketDataTable: marketData.marketDataTable, marketDataArchiveBucket: marketData.marketDataArchiveBucket
});
marketDataApi.addDependency(security);
marketDataApi.addDependency(marketData);
const brokerData = new BrokerSyncDataStack(app, 'IvanrySandboxBrokerDataStack', { env, description: 'Ivanry Sandbox broker-sync persistence; live broker sync remains disabled' });
brokerData.addDependency(security);
const corporateEvents = new CorporateEventsDataStack(app, 'IvanrySandboxCorporateEventsDataStack', { env, description: 'Ivanry Sandbox append-only income and corporate-event persistence' });
corporateEvents.addDependency(security);
const taxPlanning = new PortfolioTaxPlanningDataStack(app, 'IvanrySandboxTaxPlanningDataStack', { env, description: 'Ivanry Sandbox tax-workpaper persistence for synthetic records only' });
taxPlanning.addDependency(security);
const legalData = new PortfolioLegalDataStack(app, 'IvanrySandboxLegalDataStack', { env, description: 'Ivanry Sandbox legal-document and audit persistence' });
legalData.addDependency(security);
const quickInsightsRuntime = new PortfolioQuickInsightsRuntimeStack(app, 'IvanrySandboxQuickInsightsRuntimeStack', {
  env,
  description: 'Ivanry Sandbox retained Quick Scan AgentCore runtime',
});
const core = new PortfolioMgmtStack(app, 'IvanrySandboxCoreStack', {
  env,
  description: 'Ivanry isolated Sandbox portfolio core and preview frontend',
  brokerConnectionsTable: brokerData.brokerConnectionsTable,
  brokerSyncDataTable: brokerData.brokerSyncDataTable,
  instrumentsTable: brokerData.instrumentsTable,
  fxRatesTable: brokerData.fxRatesTable,
  corporateEventsTable: corporateEvents.eventsTable,
  taxCarriedLossesTable: taxPlanning.carriedLossesTable,
  legalDocumentsTable: legalData.legalDocumentsTable,
  insightsAgentRuntimeArn: quickInsightsRuntime.orchestratorRuntimeArn,
  webhookReceiptsTable: security.webhookReceiptsTable,
  providerSecretsKey: security.providerSecretsKey,
  cdrConsentsTable: security.consentTable,
  deletionRequestsTable: security.deletionRequestsTable,
  marketDataTable: marketData.marketDataTable,
  marketDataArchiveBucket: marketData.marketDataArchiveBucket,
  marketDataFunctions: marketDataApi.functions
});
core.addDependency(security);
core.addDependency(marketDataApi);
core.addDependency(brokerData);
core.addDependency(corporateEvents);
core.addDependency(taxPlanning);
core.addDependency(legalData);
core.addDependency(quickInsightsRuntime);
app.synth();
