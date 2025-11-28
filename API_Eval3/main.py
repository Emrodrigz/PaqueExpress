from datetime import datetime, timedelta
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Depends, Header
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime
from sqlalchemy.orm import sessionmaker, declarative_base, Session
from pydantic import BaseModel
from passlib.context import CryptContext
from jose import jwt, JWTError
import shutil, os

app = FastAPI()
os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DATABASE_URL = "mysql+pymysql://root:root@localhost/eval3"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

class Agente(Base):
    __tablename__ = "agentes"
    id = Column(Integer, primary_key=True)
    nombre = Column(String(100))
    email = Column(String(120), unique=True, index=True)
    password_hash = Column(String(255))

class Paquete(Base):
    __tablename__ = "paquetes"
    id = Column(Integer, primary_key=True)
    paquete_uid = Column(String(64), unique=True)
    direccion = Column(String(255))
    lat = Column(Float)
    lon = Column(Float)

class Entrega(Base):
    __tablename__ = "entregas"
    id = Column(Integer, primary_key=True)
    paquete_id = Column(Integer)
    agente_id = Column(Integer)
    foto_url = Column(String(255))
    gps_lat = Column(Float)
    gps_lon = Column(Float)
    fecha = Column(DateTime, default=datetime.utcnow)

Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")
JWT_SECRET = "CLAVE_SECRETA_PAQUEXPRESS_2025"
JWT_ALGO = "HS256"
JWT_EXPIRE_MINUTES = 60
BASE_API_URL = "http://127.0.0.1:8000"

def create_access_token(subject: str):
    payload = {
        "sub": subject,
        "exp": datetime.utcnow() + timedelta(minutes=JWT_EXPIRE_MINUTES),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGO)

def get_token(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Token faltante o inválido")
    return authorization.split(" ", 1)[1]

def get_current_agent(token: str = Depends(get_token), db: Session = Depends(get_db)):
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGO])
        email = payload.get("sub")
        if not email:
            raise HTTPException(status_code=401, detail="Token inválido")
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido o expirado")
    agente = db.query(Agente).filter(Agente.email == email).first()
    if not agente:
        raise HTTPException(status_code=401, detail="Usuario no existe")
    return agente

class LoginOut(BaseModel):
    access_token: str
    token_type: str = "bearer"

class PaqueteOut(BaseModel):
    id: int
    paquete_uid: str
    direccion: str
    lat: float
    lon: float
    class Config:
        from_attributes = True

class ConfirmEntregaIn(BaseModel):
    paquete_id: int
    gps_lat: float
    gps_lon: float
    foto_url: str

@app.get("/")
def read_root():
    return {"status": "API Paquexpress Online"}

@app.post("/auth/register")
def register(nombre: str = Form(...), email: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
    if db.query(Agente).filter(Agente.email == email).first():
        raise HTTPException(status_code=400, detail="Email ya registrado")
    hashed = pwd_context.hash(password)
    agente = Agente(nombre=nombre, email=email, password_hash=hashed)
    db.add(agente)
    db.commit()
    return {"msg": "Usuario creado"}

@app.post("/auth/login", response_model=LoginOut)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    agente = db.query(Agente).filter(Agente.email == form.username).first()
    if not agente or not pwd_context.verify(form.password, agente.password_hash):
        raise HTTPException(status_code=401, detail="Credenciales inválidas")
    token = create_access_token(agente.email)
    return {"access_token": token, "token_type": "bearer"}

@app.get("/paquetes/{paquete_id}", response_model=PaqueteOut)
def obtener_paquete(paquete_id: int, db: Session = Depends(get_db)):
    paquete = db.query(Paquete).filter(Paquete.id == paquete_id).first()
    if not paquete:
        raise HTTPException(status_code=404, detail="Paquete no encontrado")
    return paquete

@app.post("/fotos/")
async def subir_foto(file: UploadFile = File(...)):
    ext = os.path.splitext(file.filename)[1]
    nombre_seguro = f"foto_{datetime.now().strftime('%Y%m%d%H%M%S')}{ext}"
    ruta_local = f"uploads/{nombre_seguro}"
    with open(ruta_local, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    url_publica = f"{BASE_API_URL}/uploads/{nombre_seguro}"
    return {"ruta": url_publica}

@app.post("/entregas/confirmar")
def confirmar_entrega(body: ConfirmEntregaIn, agente: Agente = Depends(get_current_agent), db: Session = Depends(get_db)):
    entrega = Entrega(
        paquete_id=body.paquete_id,
        agente_id=agente.id,
        foto_url=body.foto_url,
        gps_lat=body.gps_lat,
        gps_lon=body.gps_lon,
        fecha=datetime.utcnow(),
    )
    db.add(entrega)
    db.commit()
    return {"msg": "Entrega confirmada"}