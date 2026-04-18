import software.amazon.awssdk.services.sts.StsClient;

public class SmokeTest {
  public static void main(String[] args) {
    try (StsClient sts = StsClient.create()) {
      System.out.println(sts.getCallerIdentity().arn());
    }
  }
}
