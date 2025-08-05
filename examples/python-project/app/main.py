from fastapi import FastAPI
from typing import Dict

app = FastAPI()

@app.get("/")
def read_root() -> Dict[str, str]:
    """
    루트 경로('/')로 접속 시 간단한 환영 메시지를 반환합니다.
    """
    return {"message": "Hello, World!"}

@app.get("/health")
def health_check() -> Dict[str, str]:
    """
    Docker의 HEALTHCHECK 지시어에서 사용하는 경로입니다.
    애플리케이션이 정상적으로 응답하는지 확인하기 위해 사용됩니다.
    HTTP 200 OK 상태 코드와 함께 간단한 JSON 응답을 반환합니다.
    """
    return {"status": "ok"}