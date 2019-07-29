package routing

import (
	"fmt"
	"regexp"

	"github.com/cloudfoundry-incubator/cf-test-helpers/cf"
	cf_helpers "github.com/cloudfoundry-incubator/cf-test-helpers/helpers"
	. "github.com/cloudfoundry/cf-acceptance-tests/cats_suite_helpers"
	"github.com/cloudfoundry/cf-acceptance-tests/helpers/app_helpers"
	"github.com/cloudfoundry/cf-acceptance-tests/helpers/assets"
	"github.com/cloudfoundry/cf-acceptance-tests/helpers/logs"
	"github.com/cloudfoundry/cf-acceptance-tests/helpers/random_name"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
	. "github.com/onsi/gomega/gexec"
)

var _ = ZipkinDescribe("Zipkin Tracing", func() {
	var (
		app1              string
		helloRoutingAsset = assets.NewAssets().SpringSleuthZip
		hostname          string
	)

	BeforeEach(func() {
		app1 = random_name.CATSRandomName("APP")
		Expect(cf.Cf("push",
			app1,
			"-b", Config.GetJavaBuildpackName(),
			"-m", "1024M",
			"-p", helloRoutingAsset,
			"-d", Config.GetAppsDomain()).Wait(CF_JAVA_TIMEOUT)).To(Exit(0))

		hostname = app1
	})

	AfterEach(func() {
		app_helpers.AppReport(app1)
		Expect(cf.Cf("delete", app1, "-f", "-r").Wait()).To(Exit(0))
	})

	Context("when zipkin tracing is enabled", func() {
		Context("when zipkin headers are not in the request", func() {
			It("the sleuth error response has no error", func() {
				// when req does not have headers
				Eventually(func() string {
					curlOutput := cf_helpers.CurlAppRoot(Config, hostname)
					return curlOutput
				}).Should(ContainSubstring("parents:"))

				var parentSpanID string
				Eventually(func() *gbytes.Buffer {
					out := logs.Tail(Config.GetUseLogCache(), app1)()
					parentSpanID = getID(`x_b3_parentspanid:"([0-9a-fA-F-]*)"`, string(out.Contents()))
					return out
				}).Should(gbytes.Say("x_b3_traceid"))
				Expect(parentSpanID).To(Equal("-"))
			})
		})

		Context("when zipkin headers are in the request", func() {
			It("the sleuth error response has no error", func() {
				traceID := "fee1f7ba6aeec41c"

				header1 := fmt.Sprintf(`X-B3-TraceId: %s `, traceID)
				header2 := `X-B3-SpanId: 579b36fd31cd8714`

				var curlOutput string
				Eventually(func() string {
					curlOutput = cf_helpers.CurlApp(Config, hostname, "/", "-H", header1, "-H", header2)
					return curlOutput
				}).Should(ContainSubstring("parents:"))

				var appLogSpanID string
				Eventually(func() *gbytes.Buffer {
					out := logs.Tail(Config.GetUseLogCache(), hostname)()
					spanIDRegex := fmt.Sprintf("x_b3_traceid:\"%s\" x_b3_spanid:\"([0-9a-fA-F]*)\"", traceID)
					appLogSpanID = getID(spanIDRegex, string(out.Contents()))
					return out
				}).Should(gbytes.Say(fmt.Sprintf(`x_b3_traceid:"%s"`, traceID)))

				Expect(curlOutput).To(ContainSubstring(traceID))
				Expect(curlOutput).To(ContainSubstring(fmt.Sprintf("parents: [%s]", appLogSpanID)))
			})
		})
	})
})

func getID(logRegex, logLines string) string {
	matches := regexp.MustCompile(logRegex).FindStringSubmatch(logLines)
	if len(matches) != 2 {
		return ""
	}

	return matches[1]
}
