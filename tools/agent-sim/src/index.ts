import { runHappyPath } from "./scenarios/happy-path.js";
import { runDisagreement } from "./scenarios/disagreement.js";
import { runRealLlm } from "./scenarios/real-llm.js";

const API_URL = process.env.VERITAS_API_URL ?? "http://localhost:8080";

function parseArgs(): { scenario: string } {
  const args = process.argv.slice(2);
  let scenario = "all";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--scenario" && args[i + 1]) {
      scenario = args[i + 1];
      i++;
    }
  }

  return { scenario };
}

async function main() {
  const { scenario } = parseArgs();

  console.log("Veritas Agent Simulator");
  console.log(`API URL: ${API_URL}`);
  console.log(`Scenario: ${scenario}`);

  try {
    switch (scenario) {
      case "happy-path":
        await runHappyPath(API_URL);
        break;
      case "disagreement":
        await runDisagreement(API_URL);
        break;
      case "real-llm":
        await runRealLlm(API_URL);
        break;
      case "all":
        await runHappyPath(API_URL);
        await runDisagreement(API_URL);
        await runRealLlm(API_URL);
        break;
      default:
        console.error(`Unknown scenario: ${scenario}`);
        console.error(
          "Available: happy-path, disagreement, real-llm, all"
        );
        process.exit(1);
    }
  } catch (err) {
    console.error("\nError:", err instanceof Error ? err.message : err);
    process.exit(1);
  }
}

main();
