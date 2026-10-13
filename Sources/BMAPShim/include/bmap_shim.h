/*
 * Blizzard BMAP shim: the only API Swift sees (ADR-0002).
 *
 * Pure C. Every function is safe to call from Swift: no C++ exception crosses this boundary.
 * The shim is single-threaded. Call every function on BMAPThread, and never re-enter the shim
 * from inside a blz_send_recv_fn callback.
 *
 * Bump BLZ_ABI_VERSION on any change to a type or signature in this file.
 */
#ifndef BLIZZARD_BMAP_SHIM_H
#define BLIZZARD_BMAP_SHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
#define BLZ_NOEXCEPT noexcept
extern "C" {
#else
#define BLZ_NOEXCEPT
#endif

#define BLZ_ABI_VERSION 2u

typedef enum blz_status {
    BLZ_OK = 0,
    BLZ_ERR_CONNECT,     /* the link could not be opened or used */
    BLZ_ERR_BUSY,        /* another BMAP client holds the headset */
    BLZ_ERR_TIMEOUT,     /* no reply in time */
    BLZ_ERR_CLOSED,      /* the link closed during the call */
    BLZ_ERR_DEVICE,      /* the headset answered ERROR; see blz_last_device_error */
    BLZ_ERR_UNSUPPORTED, /* the feature is not enabled for this device */
    BLZ_ERR_DESYNC,      /* the reply came from a different address than the request */
    BLZ_ERR_DENIED,      /* the allowlist refused the packet (a programmer bug) */
    BLZ_ERR_PARSE,       /* the reply was missing, truncated or malformed */
    BLZ_ERR_INVALID_ARG, /* a bad argument (a programmer bug) */
    BLZ_ERR_INTERNAL,    /* anything else */
    BLZ_STATUS_MAX_ENUM = 0x7FFFFFFF /* not a status: widens the type so any value Swift passes is defined */
} blz_status;

typedef enum blz_profile {
    BLZ_PROFILE_APP = 0,
    BLZ_PROFILE_PROBE,
    BLZ_PROFILE_REPLAY,
    BLZ_PROFILE_MAX_ENUM = 0x7FFFFFFF /* not a profile: widens the type, as above */
} blz_profile;

typedef struct blz_session blz_session;

/*
 * Sends one packet and receives the reply bytes. Called on BMAPThread, synchronously.
 * `drain` asks the link to keep reading until silence (multi-frame replies).
 * Write at most `out_cap` bytes to `out` and the count to `*out_len`.
 * Return BLZ_OK, or one of BLZ_ERR_CONNECT, BLZ_ERR_BUSY, BLZ_ERR_TIMEOUT or BLZ_ERR_CLOSED.
 * Any other status is reported to the caller as BLZ_ERR_INTERNAL.
 * Must not call back into the shim.
 */
typedef blz_status (*blz_send_recv_fn)(void *ctx, const uint8_t *pkt, size_t pkt_len, bool drain,
                                       uint8_t *out, size_t out_cap, size_t *out_len);

/* The BLZ_ABI_VERSION this library was built with. */
uint32_t blz_abi_version(void) BLZ_NOEXCEPT;

/*
 * Creates a session that sends through `fn` with `ctx`. Returns NULL if `fn` is NULL, the
 * profile is unknown, or allocation fails. The shim never retains or releases `ctx`; it must stay
 * valid until blz_session_destroy returns.
 */
blz_session *blz_session_create(blz_send_recv_fn fn, void *ctx, blz_profile profile) BLZ_NOEXCEPT;

/* Destroys a session. NULL is a no-op. */
void blz_session_destroy(blz_session *s) BLZ_NOEXCEPT;

/* Sends GET [0.1] (BMAP version / init) and checks the headset answers it. */
blz_status blz_init(blz_session *s) BLZ_NOEXCEPT;

/* The BMAP error code from the last BLZ_ERR_DEVICE, or 0. */
uint8_t blz_last_device_error(const blz_session *s) BLZ_NOEXCEPT;

/*
 * Copies the last error message, NUL-terminated and truncated to `cap`, into `buf`.
 * Returns the full message length, excluding the NUL. The message is empty after a call
 * that returned BLZ_OK. `buf` may be NULL when `cap` is 0.
 */
size_t blz_last_error_message(const blz_session *s, char *buf, size_t cap) BLZ_NOEXCEPT;

/*
 * True if `profile` may send `pkt` (the allowlist CallbackTransport applies to every outbound packet).
 * Pure function with no session; it exists so tests and tools can check the policy directly.
 * Never use it to decide whether to send: every send path already checks it.
 */
bool blz_packet_allowed(blz_profile profile, const uint8_t *pkt, size_t len) BLZ_NOEXCEPT;

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* BLIZZARD_BMAP_SHIM_H */
