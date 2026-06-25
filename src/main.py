import time

from fastapi import FastAPI
from prometheus_client import Counter, Gauge, Histogram
from prometheus_fastapi_instrumentator import Instrumentator

from src.schemas import PredictionRequest, PredictionResponse
from src.model import SentimentModel

app = FastAPI(title="SentimentAI", version="0.1.0")

# Métriques Prometheus personnalisées
PREDICTIONS_TOTAL = Counter(
    "sentiment_predictions_total",
    "Nombre total de prédictions par label",
    ["label"],
)

CONFIDENCE_SCORE = Gauge(
    "sentiment_confidence_score",
    "Score de confiance de la dernière prédiction",
)

PREDICTION_DURATION = Histogram(
    "sentiment_prediction_duration_seconds",
    "Durée des prédictions en secondes",
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
)

# Instrumentateur HTTP automatique -- expose /metrics
Instrumentator().instrument(app).expose(app)

model = SentimentModel()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/predict", response_model=PredictionResponse)
def predict(request: PredictionRequest):
    start = time.time()
    result = model.predict(request.text)
    duration = time.time() - start

    PREDICTIONS_TOTAL.labels(label=result["label"]).inc()
    CONFIDENCE_SCORE.set(result["score"])
    PREDICTION_DURATION.observe(duration)

    return result
