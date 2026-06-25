#include "whisper.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>

#if defined(_WIN32)
#define RUNE_WHISPER_EXPORT __declspec(dllexport)
#else
#define RUNE_WHISPER_EXPORT __attribute__((visibility("default")))
#endif

struct RuneWhisperContext {
    whisper_context * ctx = nullptr;
    std::string last_error;
    std::mutex mutex;
};

namespace {
std::mutex g_error_mutex;
std::string g_last_error;

void set_global_error(const std::string & message) {
    std::lock_guard<std::mutex> lock(g_error_mutex);
    g_last_error = message;
}

const char * global_error() {
    std::lock_guard<std::mutex> lock(g_error_mutex);
    if (g_last_error.empty()) {
        g_last_error = "Unknown whisper.cpp error.";
    }
    return g_last_error.c_str();
}

void set_error(RuneWhisperContext * handle, const std::string & message) {
    if (handle == nullptr) {
        set_global_error(message);
        return;
    }
    handle->last_error = message;
}

char * copy_string(const std::string & value) {
    const auto size = value.size() + 1;
    auto * out = static_cast<char *>(std::malloc(size));
    if (out == nullptr) return nullptr;
    std::memcpy(out, value.c_str(), size);
    return out;
}

int worker_threads() {
    const auto available = std::thread::hardware_concurrency();
    if (available == 0) return 2;
    return std::max(1u, std::min(4u, available));
}
}

extern "C" {

RUNE_WHISPER_EXPORT RuneWhisperContext * rune_whisper_create(
        const char * model_path) {
    if (model_path == nullptr || model_path[0] == '\0') {
        set_global_error("Whisper model path is empty.");
        return nullptr;
    }

    auto * handle = new RuneWhisperContext();
    auto params = whisper_context_default_params();
    params.use_gpu = false;

    handle->ctx = whisper_init_from_file_with_params(model_path, params);
    if (handle->ctx == nullptr) {
        set_error(handle, "Failed to load whisper.cpp model.");
        set_global_error(handle->last_error);
        delete handle;
        return nullptr;
    }

    return handle;
}

RUNE_WHISPER_EXPORT void rune_whisper_destroy(RuneWhisperContext * handle) {
    if (handle == nullptr) return;
    if (handle->ctx != nullptr) whisper_free(handle->ctx);
    delete handle;
}

RUNE_WHISPER_EXPORT char * rune_whisper_transcribe(
        RuneWhisperContext * handle,
        const float * samples,
        int sample_count,
        const char * language) {
    if (handle == nullptr || handle->ctx == nullptr) {
        set_global_error("Whisper context is not initialized.");
        return nullptr;
    }
    if (samples == nullptr || sample_count <= 0) {
        std::lock_guard<std::mutex> lock(handle->mutex);
        set_error(handle, "No audio samples were provided.");
        return nullptr;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    try {
        auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        params.n_threads = worker_threads();
        params.translate = false;
        params.no_context = true;
        params.no_timestamps = true;
        params.print_special = false;
        params.print_progress = false;
        params.print_realtime = false;
        params.print_timestamps = false;
        params.language =
                (language == nullptr || language[0] == '\0') ? "en" : language;
        params.detect_language = false;

        const int status =
                whisper_full(handle->ctx, params, samples, sample_count);
        if (status != 0) {
            std::ostringstream message;
            message << "whisper_full failed with status " << status << ".";
            set_error(handle, message.str());
            return nullptr;
        }

        std::string transcript;
        const int segments = whisper_full_n_segments(handle->ctx);
        for (int i = 0; i < segments; i++) {
            const char * segment =
                    whisper_full_get_segment_text(handle->ctx, i);
            if (segment != nullptr) transcript += segment;
        }

        auto * out = copy_string(transcript);
        if (out == nullptr) {
            set_error(handle, "Failed to allocate transcription result.");
        }
        return out;
    } catch (const std::exception & error) {
        set_error(handle, error.what());
        return nullptr;
    } catch (...) {
        set_error(handle, "Unknown whisper.cpp exception.");
        return nullptr;
    }
}

RUNE_WHISPER_EXPORT void rune_whisper_free_string(char * value) {
    std::free(value);
}

RUNE_WHISPER_EXPORT const char * rune_whisper_last_error(
        RuneWhisperContext * handle) {
    if (handle == nullptr) return global_error();
    if (handle->last_error.empty()) return "Unknown whisper.cpp error.";
    return handle->last_error.c_str();
}

RUNE_WHISPER_EXPORT const char * rune_whisper_version() {
    return whisper_version();
}

}
