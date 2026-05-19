import argparse
import platform
import sys


def run_doctor() -> int:
    print("=== AVoc Doctor ===")
    failures: list[str] = []

    try:
        import torch
    except Exception as exc:
        failures.append(f"torch import failed: {exc}")
        torch = None  # type: ignore[assignment]

    if torch is not None:
        print(f"torch version: {getattr(torch, '__version__', 'unknown')}")
        try:
            cuda_available = bool(torch.cuda.is_available())
            print(f"torch.cuda.is_available(): {cuda_available}")
            if not cuda_available:
                failures.append("CUDA is not available in torch")
            else:
                device_name = torch.cuda.get_device_name(0)
                print(f"CUDA device: {device_name}")
        except Exception as exc:
            failures.append(f"torch CUDA check failed: {exc}")

    try:
        import onnxruntime as ort

        providers = ort.get_available_providers()
        print(f"ONNX Runtime providers: {providers}")
        if "CUDAExecutionProvider" not in providers:
            failures.append("ONNX Runtime CUDAExecutionProvider is not available")
    except Exception as exc:
        failures.append(f"onnxruntime check failed: {exc}")

    if failures:
        print("\nDoctor status: FAILED")
        for failure in failures:
            print(f" - {failure}")
        print("\nActionable remediation:")
        print("  1) Verify NVIDIA driver installation and compatibility for your GPU/CUDA runtime.")
        if platform.system() == "Windows":
            print("     Recommended check: nvidia-smi (Command Prompt or PowerShell).")
        else:
            print("     Recommended check: nvidia-smi")
        print("  2) Reboot the system after installing/updating GPU drivers.")
        print("  3) Reinstall dependencies:")
        print("     Linux/macOS: ./.venv/bin/python -m pip install -r requirements-3.12.3.txt")
        print("     Windows    : .\\.venv\\Scripts\\python.exe -m pip install -r requirements-3.12.3.txt")
        return 1

    print("Doctor status: OK")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--doctor", action="store_true")
    args, remaining = parser.parse_known_args()

    if args.doctor:
        raise SystemExit(run_doctor())

    # For pyside6-deploy and the debugger.
    from src.avoc.main import main as gui_main

    sys.argv = [sys.argv[0], *remaining]
    gui_main()

if __name__ == "__main__":
    main()
