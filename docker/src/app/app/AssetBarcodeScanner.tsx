"use client";

import { useEffect, useRef, useState } from "react";

type BarcodeDetectorResult = {
  rawValue: string;
};

type BarcodeDetectorInstance = {
  detect(source: CanvasImageSource): Promise<BarcodeDetectorResult[]>;
};

type ScannerControls = {
  stop: () => void;
};

type ZxingResult = {
  getText?: () => string;
  text?: string;
};

type BrowserReader = {
  decodeFromCanvas: (canvas: HTMLCanvasElement) => Promise<unknown> | unknown;
  decodeFromVideoDevice?: (
    deviceId: string | undefined,
    previewElem: HTMLVideoElement,
    callbackFn: (result: unknown, error: unknown, controls: ScannerControls) => void
  ) => Promise<ScannerControls>;
};

declare global {
  interface Window {
    BarcodeDetector?: new (options?: { formats?: string[] }) => BarcodeDetectorInstance;
  }
}

const barcodeFormats = [
  "code_128",
  "code_39",
  "code_93",
  "codabar",
  "ean_13",
  "ean_8",
  "itf",
  "upc_a",
  "upc_e",
  "qr_code"
];

function resultText(result: unknown) {
  const value = result as ZxingResult | null | undefined;
  return value?.getText?.() || value?.text || "";
}

function clampChannel(value: number) {
  return Math.max(0, Math.min(255, value));
}

async function loadImage(url: string) {
  const image = new Image();
  image.decoding = "async";
  image.src = url;
  await image.decode().catch(
    () =>
      new Promise<void>((resolve, reject) => {
        image.onload = () => resolve();
        image.onerror = () => reject(new Error("image load failed"));
      })
  );
  return image;
}

function drawImageCanvas(image: HTMLImageElement, rotate: number, cropRatio: number) {
  const naturalWidth = image.naturalWidth || image.width;
  const naturalHeight = image.naturalHeight || image.height;
  const cropWidth = naturalWidth * cropRatio;
  const cropHeight = naturalHeight * cropRatio;
  const sourceX = (naturalWidth - cropWidth) / 2;
  const sourceY = (naturalHeight - cropHeight) / 2;
  const scale = Math.min(2200 / cropWidth, 2200 / cropHeight, 2);
  const targetWidth = Math.max(1, Math.round(cropWidth * scale));
  const targetHeight = Math.max(1, Math.round(cropHeight * scale));
  const rotated = rotate % 180 !== 0;
  const canvas = document.createElement("canvas");
  canvas.width = rotated ? targetHeight : targetWidth;
  canvas.height = rotated ? targetWidth : targetHeight;

  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) return canvas;
  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = "high";
  context.translate(canvas.width / 2, canvas.height / 2);
  context.rotate((rotate * Math.PI) / 180);
  context.drawImage(image, sourceX, sourceY, cropWidth, cropHeight, -targetWidth / 2, -targetHeight / 2, targetWidth, targetHeight);
  return canvas;
}

function filterCanvas(source: HTMLCanvasElement, mode: "contrast" | "binary") {
  const canvas = document.createElement("canvas");
  canvas.width = source.width;
  canvas.height = source.height;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  const sourceContext = source.getContext("2d", { willReadFrequently: true });
  if (!context || !sourceContext) return canvas;

  context.drawImage(source, 0, 0);
  const imageData = context.getImageData(0, 0, canvas.width, canvas.height);
  const data = imageData.data;
  for (let index = 0; index < data.length; index += 4) {
    const gray = data[index] * 0.299 + data[index + 1] * 0.587 + data[index + 2] * 0.114;
    const value = mode === "binary" ? (gray > 142 ? 255 : 0) : clampChannel((gray - 128) * 1.75 + 128);
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
  }
  context.putImageData(imageData, 0, 0);
  return canvas;
}

async function decodeCanvasWithNative(canvas: HTMLCanvasElement, detector: BarcodeDetectorInstance | null) {
  if (!detector) return "";
  const codes = await detector.detect(canvas);
  return codes[0]?.rawValue?.trim() || "";
}

async function zxingReaders() {
  const { BrowserMultiFormatReader, BrowserMultiFormatOneDReader } = await import("@zxing/browser");
  return [new BrowserMultiFormatOneDReader(), new BrowserMultiFormatReader()] as BrowserReader[];
}

async function decodeCanvasWithZxing(canvas: HTMLCanvasElement, readers: BrowserReader[]) {
  for (const reader of readers) {
    try {
      const code = resultText(await reader.decodeFromCanvas(canvas)).trim();
      if (code) return code;
    } catch {
      // Try the next reader or image preprocessing variant.
    }
  }
  return "";
}

async function decodePreparedCanvases(image: HTMLImageElement) {
  const nativeDetector = window.BarcodeDetector ? new window.BarcodeDetector({ formats: barcodeFormats }) : null;
  const readers = await zxingReaders();
  const variants: HTMLCanvasElement[] = [];
  for (const cropRatio of [1, 0.82, 0.64]) {
    for (const rotate of [0, 90, 180, 270]) {
      const base = drawImageCanvas(image, rotate, cropRatio);
      variants.push(base, filterCanvas(base, "contrast"), filterCanvas(base, "binary"));
    }
  }

  for (const canvas of variants) {
    const nativeCode = await decodeCanvasWithNative(canvas, nativeDetector).catch(() => "");
    if (nativeCode) return nativeCode;
    const zxingCode = await decodeCanvasWithZxing(canvas, readers);
    if (zxingCode) return zxingCode;
  }
  return "";
}

export function AssetBarcodeScanner() {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const photoRef = useRef<HTMLInputElement>(null);
  const uploadRef = useRef<HTMLInputElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const frameRef = useRef<number | null>(null);
  const detectorRef = useRef<BarcodeDetectorInstance | null>(null);
  const zxingControlsRef = useRef<ScannerControls | null>(null);
  const [manualCode, setManualCode] = useState("");
  const [message, setMessage] = useState("实时扫码需要 HTTPS；如果手机提示不安全，请先安装并信任本地 CA 证书。");
  const [isScanning, setIsScanning] = useState(false);
  const [isDecodingImage, setIsDecodingImage] = useState(false);

  useEffect(() => {
    return () => stopCamera();
  }, []);

  function locateAsset(code: string) {
    const value = code.trim();
    if (!value) return;
    stopCamera();
    dialogRef.current?.close();
    window.location.assign(`/app?q=${encodeURIComponent(value)}&operate=1`);
  }

  async function startCamera() {
    if (!window.isSecureContext) {
      setMessage("实时扫码被浏览器拦截：请使用 https://10.10.10.71，并确认手机已信任本地 CA 证书。");
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      setMessage("当前浏览器不支持实时摄像头，请使用拍照识别或相册识别。");
      return;
    }

    try {
      setMessage("正在打开摄像头");
      if (window.BarcodeDetector) {
        detectorRef.current = new window.BarcodeDetector({ formats: barcodeFormats });
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: "environment" } },
          audio: false
        });
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }
        setIsScanning(true);
        setMessage("对准条形码，识别后会自动定位资产");
        scanFrame();
        return;
      }

      const { BrowserMultiFormatReader } = await import("@zxing/browser");
      const reader = new BrowserMultiFormatReader() as BrowserReader;
      if (!videoRef.current || !reader.decodeFromVideoDevice) throw new Error("当前浏览器不支持实时条码识别");
      zxingControlsRef.current = await reader.decodeFromVideoDevice(undefined, videoRef.current, (result) => {
        const code = resultText(result).trim();
        if (code) locateAsset(code);
      });
      setIsScanning(true);
      setMessage("对准条形码，识别后会自动定位资产");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "摄像头打开失败，请改用拍照识别");
      stopCamera();
    }
  }

  async function scanFrame() {
    const video = videoRef.current;
    const detector = detectorRef.current;
    if (!video || !detector || video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
      frameRef.current = window.requestAnimationFrame(scanFrame);
      return;
    }

    try {
      const codes = await detector.detect(video);
      const code = codes[0]?.rawValue?.trim();
      if (code) {
        locateAsset(code);
        return;
      }
    } catch {
      setMessage("识别失败，请调整距离或光线");
    }
    frameRef.current = window.requestAnimationFrame(scanFrame);
  }

  async function decodeImageFile(file: File) {
    setIsDecodingImage(true);
    setMessage("正在识别图片，请保持条码清晰且占画面较大比例");
    const objectUrl = URL.createObjectURL(file);
    try {
      const image = await loadImage(objectUrl);
      const code = await decodePreparedCanvases(image);
      if (code) {
        locateAsset(code);
        return;
      }
      setMessage("没有识别到条形码。请让条码占画面三分之一以上、对焦清晰，或手动输入外编号。");
    } catch {
      setMessage("图片读取失败，请重新拍照或手动输入外编号。");
    } finally {
      URL.revokeObjectURL(objectUrl);
      setIsDecodingImage(false);
      if (photoRef.current) photoRef.current.value = "";
      if (uploadRef.current) uploadRef.current.value = "";
    }
  }

  function stopCamera() {
    if (frameRef.current) {
      window.cancelAnimationFrame(frameRef.current);
      frameRef.current = null;
    }
    zxingControlsRef.current?.stop();
    zxingControlsRef.current = null;
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setIsScanning(false);
  }

  function openScanner() {
    setManualCode("");
    setMessage("实时扫码需要 HTTPS；如果手机提示不安全，请先安装并信任本地 CA 证书。");
    dialogRef.current?.showModal();
  }

  return (
    <>
      <button className="button secondary" type="button" onClick={openScanner}>
        扫码定位
      </button>
      <dialog className="dialog scanner-dialog" ref={dialogRef} onClose={stopCamera}>
        <div className="form">
          <div className="section-head">
            <h2>扫码定位资产</h2>
            <button className="button secondary" type="button" onClick={() => dialogRef.current?.close()}>
              关闭
            </button>
          </div>
          <div className="scanner-frame">
            <video className="scanner-video" ref={videoRef} muted playsInline />
            <div className="scanner-line" />
          </div>
          <p className="muted">{message}</p>
          <input
            ref={photoRef}
            className="hidden-file"
            type="file"
            accept="image/*"
            capture="environment"
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file) void decodeImageFile(file);
            }}
          />
          <input
            ref={uploadRef}
            className="hidden-file"
            type="file"
            accept="image/*"
            onChange={(event) => {
              const file = event.target.files?.[0];
              if (file) void decodeImageFile(file);
            }}
          />
          <div className="actions scanner-actions">
            <button className="button blue" type="button" onClick={startCamera} disabled={isScanning || isDecodingImage}>
              实时扫码
            </button>
            <button className="button secondary" type="button" onClick={() => photoRef.current?.click()} disabled={isDecodingImage}>
              拍照识别
            </button>
            <button className="button secondary" type="button" onClick={() => uploadRef.current?.click()} disabled={isDecodingImage}>
              相册识别
            </button>
            <button className="button secondary" type="button" onClick={stopCamera} disabled={!isScanning}>
              停止
            </button>
          </div>
          <form
            className="form"
            onSubmit={(event) => {
              event.preventDefault();
              locateAsset(manualCode);
            }}
          >
            <div className="field">
              <label>手动输入外编号</label>
              <input className="input" value={manualCode} onChange={(event) => setManualCode(event.target.value)} inputMode="text" />
            </div>
            <button className="button secondary" type="submit">
              定位
            </button>
          </form>
        </div>
      </dialog>
    </>
  );
}
