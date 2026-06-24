"""
run_evaluation.py
Runs Foundry batch evaluation and writes results.json for GitHub Actions to consume.
"""
import argparse, json, os, sys
from azure.ai.evaluation import (
    evaluate, RelevanceEvaluator, CoherenceEvaluator,
    FluencyEvaluator, GroundednessEvaluator,
)
THRESHOLDS = {
    "relevance":   4.0,
    "coherence":   4.0,
    "fluency":     4.0,
    "groundedness": 3.0,
}
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--test-data", required=True, help="Path to JSONL with query, context, response")
    p.add_argument("--output", default="results.json")
    args = p.parse_args()
    # Required env vars
    endpoint   = os.environ["FOUNDRY_PROJECT_ENDPOINT"]
    deployment = os.environ.get("MODEL_DEPLOYMENT", "gpt-4.1-mini")
    base_endpoint = endpoint.split("/api/projects/")[0]
    model_config = {
        "azure_endpoint":   base_endpoint,
        "azure_deployment": deployment,
    }
    # Foundry project config — logs results to Foundry UI
    azure_ai_project = {
        "subscription_id":   os.environ.get("AZURE_SUBSCRIPTION_ID", "2bd16cbc-e160-4498-b312-48fb818596a9"),
        "resource_group_name": os.environ.get("AZURE_RESOURCE_GROUP", "ai_300"),
        "project_name":      os.environ.get("AZURE_PROJECT_NAME", "klohar-ai300-genaiops"),
    }
    evaluators = {
        "relevance":    RelevanceEvaluator(model_config),
        "coherence":    CoherenceEvaluator(model_config),
        "fluency":      FluencyEvaluator(model_config),
        "groundedness": GroundednessEvaluator(model_config),
    }
    print("[run_evaluation] Starting batch evaluation...")
    result = evaluate(
        data=args.test_data,
        evaluators=evaluators,
        evaluator_config={
            "relevance":    {"column_mapping": {"query": "${data.query}", "response": "${data.response}"}},
            "coherence":    {"column_mapping": {"query": "${data.query}", "response": "${data.response}"}},
            "fluency":      {"column_mapping": {"response": "${data.response}"}},
            "groundedness": {"column_mapping": {"query": "${data.query}", "response": "${data.response}", "context": "${data.context}"}},
        },
        azure_ai_project=azure_ai_project,  # ← logs results to Foundry UI
    )
    metrics_raw = result.get("metrics", {})
    metrics = {}
    for ev in ["relevance", "coherence", "fluency", "groundedness"]:
        for cand in [f"{ev}.{ev}", f"{ev}.score", f"{ev}_score", ev]:
            if cand in metrics_raw:
                metrics[ev] = round(float(metrics_raw[cand]), 2)
                break
    passed = all(metrics.get(k, 0) >= v for k, v in THRESHOLDS.items())
    out = {
        "metrics": metrics,
        "thresholds": THRESHOLDS,
        "passed": passed,
        "total_examples": sum(1 for _ in open(args.test_data)),
    }
    with open(args.output, "w") as f:
        json.dump(out, f, indent=2)
    print(json.dumps(out, indent=2))
    sys.exit(0 if passed else 1)
if __name__ == "__main__":
    main()
