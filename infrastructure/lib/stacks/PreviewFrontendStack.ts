import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3 from 'aws-cdk-lib/aws-s3';

export interface PreviewFrontendStackProps extends cdk.StackProps {
  sourceSha: string;
  coreApiUrl: string;
  connectorApiUrl: string;
}

/**
 * Ephemeral frontend-only preview for one immutable source SHA.
 *
 * The private bucket, OAC, CloudFront function, and distribution are owned by
 * this stack. The sole integration dependency is the existing core API, reached
 * through a same-origin, GET/HEAD/OPTIONS-only `/api/*` proxy for the focused
 * Settings journey. It deliberately creates no customer-data resource.
 */
export class PreviewFrontendStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props: PreviewFrontendStackProps) {
    super(scope, id, props);

    if (!/^[a-f0-9]{40,64}$/.test(props.sourceSha)) {
      throw new Error('PreviewFrontendStack requires a full lowercase Git SHA.');
    }
    const coreApi = new URL(props.coreApiUrl);
    if (coreApi.protocol !== 'https:' || coreApi.pathname !== '/v1') {
      throw new Error('PreviewFrontendStack requires the HTTPS core API /v1 URL.');
    }
    const connectorApi = new URL(props.connectorApiUrl);
    if (connectorApi.protocol !== 'https:' || connectorApi.pathname !== '/') {
      throw new Error('PreviewFrontendStack requires the HTTPS connector API origin.');
    }

    cdk.Tags.of(this).add('ivanry:purpose', 'ephemeral-frontend-preview');
    cdk.Tags.of(this).add('ivanry:source-sha', props.sourceSha);

    const bucket = new s3.Bucket(this, 'PreviewAssets', {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      autoDeleteObjects: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    const oac = new cloudfront.S3OriginAccessControl(this, 'PreviewOac', {
      description: 'Ivanry dedicated frontend preview target',
    });
    const rewrite = new cloudfront.Function(this, 'PreviewRouteRewrite', {
      functionName: 'ivanry-preview-route-rewrite',
      comment: 'Ivanry dedicated frontend preview target',
      code: cloudfront.FunctionCode.fromInline(`
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri === '/api' || uri.indexOf('/api/') === 0) {
    request.uri = uri.slice(4) || '/';
    return request;
  }
  if (uri === '/connector' || uri.indexOf('/connector/') === 0) {
    request.uri = uri.slice(10) || '/';
    return request;
  }
  var cleanRoutes = {
    '/dashboard': true, '/help': true, '/login': true, '/portfolios': true,
    '/settings': true, '/stocks': true
  };
  var cleanUri = uri.length > 1 && uri.endsWith('/') ? uri.slice(0, -1) : uri;
  if (cleanRoutes[cleanUri]) request.uri = cleanUri + '.html';
  return request;
}
      `.trim()),
    });

    const distribution = new cloudfront.Distribution(this, 'PreviewDistribution', {
      comment: 'Ivanry dedicated frontend preview target',
      defaultRootObject: 'index.html',
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(bucket, { originAccessControl: oac }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        compress: true,
        functionAssociations: [{ function: rewrite, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST }],
      },
      additionalBehaviors: {
        '/api/*': {
          origin: new origins.HttpOrigin(coreApi.hostname, {
            originPath: coreApi.pathname,
            protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
          functionAssociations: [{ function: rewrite, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST }],
        },
        '/connector/*': {
          origin: new origins.HttpOrigin(connectorApi.hostname, {
            protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
          functionAssociations: [{ function: rewrite, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST }],
        },
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
    });

    new cdk.CfnOutput(this, 'PreviewBucketName', { value: bucket.bucketName });
    new cdk.CfnOutput(this, 'PreviewDistributionId', { value: distribution.distributionId });
    new cdk.CfnOutput(this, 'PreviewOrigin', { value: `https://${distribution.distributionDomainName}` });
    new cdk.CfnOutput(this, 'SourceSha', { value: props.sourceSha });
  }
}
