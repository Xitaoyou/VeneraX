# ImageTrans Legacy balloon detector

The obsolete balloonseg model has been removed. Legacy now means the original
Scaled YOLOv4 model used by AiNieePlus, not a segmentation model.

Source: https://github.com/Xitaoyou/AiNieePlus/releases/tag/manga-models-v1
Reference implementation: Backend/infrastructure/manga/engines.py in that repository.
Original model: https://github.com/xulihang/balloon-dataset
Model rights and restrictions remain those of the original distribution.

`python tool/convert_legacy_balloon.py` verifies the original CFG and weights by
SHA-256 and generates the ignored ONNX asset before Flutter builds. No training
or quantization is performed. The model is about 281 MB; this is intentionally
not the old 1.9 MB balloonseg model. iOS CI prepares it before tests and packaging.

The ONNX output consists of three activated heads (24 channels, 64/32/16 grid).
The Dart decoder implements new_coords=1 and scale_x_y=1.05, objectness times
class confidence >0.20 and IoU NMS 0.50, as in the original OpenCV implementation.
Local verification compared actual manga detections with the original OpenCV
network and ran the converted model through the app's Dart FFI path.

Legacy alone detects bubbles, not all captions or unframed text. The combined
panel + Legacy mode retains panel text blocks outside bubbles and splits
cross-bubble blocks by the original detector's boundaries. Existing stored
translations are preserved; retranslate a page to use the new detections.
