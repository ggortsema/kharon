from fastapi import FastAPI
import uvicorn


app = FastAPI(title="kharon")


@app.get("/")
def read_root() -> dict[str, str]:
    return {"message": "Hello world"}


def main() -> None:
    uvicorn.run("kharon.main:app", host="127.0.0.1", port=8000, reload=True)


if __name__ == "__main__":
    main()
