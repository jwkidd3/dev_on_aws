using Amazon.SecurityToken;

var sts = new AmazonSecurityTokenServiceClient();
Console.WriteLine((await sts.GetCallerIdentityAsync(new())).Arn);
