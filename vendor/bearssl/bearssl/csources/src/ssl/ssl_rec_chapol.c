/*
 * Copyright (c) 2016 Thomas Pornin <pornin@bolet.org>
 *
 * Permission is hereby granted, free of charge, to any person obtaining 
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be 
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, 
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "inner.h"

static void
gen_chapol_init(br_sslrec_chapol_context *cc,
	br_chacha20_run ichacha, br_poly1305_run ipoly,
	const void *key, const void *iv)
{
	cc->seq = 0;
	cc->ichacha = ichacha;
	cc->ipoly = ipoly;
	memcpy(cc->key, key, sizeof cc->key);
	memcpy(cc->iv, iv, sizeof cc->iv);
}

static void
gen_chapol_process(br_sslrec_chapol_context *cc,
	int record_type, unsigned version, void *data, size_t len,
	void *tag, int encrypt)
{
	unsigned char header[13];
	unsigned char nonce[12];
	uint64_t seq;
	size_t u;

	seq = cc->seq ++;
	br_enc64be(header, seq);
	header[8] = (unsigned char)record_type;
	br_enc16be(header + 9, version);
	br_enc16be(header + 11, len);
	memcpy(nonce, cc->iv, 12);
	for (u = 0; u < 8; u ++) {
		nonce[11 - u] ^= (unsigned char)seq;
		seq >>= 8;
	}
	cc->ipoly(cc->key, nonce, data, len, header, sizeof header,
		tag, cc->ichacha, encrypt);
}

static void
in_chapol_init(br_sslrec_chapol_context *cc,
	br_chacha20_run ichacha, br_poly1305_run ipoly,
	const void *key, const void *iv)
{
	cc->vtable.in = &br_sslrec_in_chapol_vtable;
	gen_chapol_init(cc, ichacha, ipoly, key, iv);
}

static int
chapol_check_length(const br_sslrec_chapol_context *cc, size_t rlen)
{
	/*
	 * Overhead is just the authentication tag (16 bytes).
	 */
	(void)cc;
	return rlen >= 16 && rlen <= (16384 + 16);
}

static unsigned char *
chapol_decrypt(br_sslrec_chapol_context *cc,
	int record_type, unsigned version, void *data, size_t *data_len)
{
	unsigned char *buf;
	size_t u, len;
	unsigned char tag[16];
	unsigned bad;

	buf = data;
	len = *data_len - 16;
	gen_chapol_process(cc, record_type, version, buf, len, tag, 0);
	bad = 0;
	for (u = 0; u < 16; u ++) {
		bad |= tag[u] ^ buf[len + u];
	}
	if (bad) {
		return NULL;
	}
	*data_len = len;
	return buf;
}

/* see bearssl_ssl.h */
static int
chapol_check_length_wrapper(const br_sslrec_in_class *const * a0, size_t a1)
{
	return chapol_check_length((void *)a0, a1);
}

static unsigned char *
chapol_decrypt_wrapper(const br_sslrec_in_class ** a0,
			int a1, unsigned a2, void * a3, size_t * a4)
{
	return chapol_decrypt((void *)a0, a1, a2, a3, a4);
}

static void
in_chapol_init_wrapper(const br_sslrec_in_chapol_class ** a0,
		br_chacha20_run a1, br_poly1305_run a2,
		const void * a3, const void * a4)
{
	in_chapol_init((void *)a0, a1, a2, a3, a4);
}

const br_sslrec_in_chapol_class br_sslrec_in_chapol_vtable = {
	{
		sizeof(br_sslrec_chapol_context),
		&chapol_check_length_wrapper,
		&chapol_decrypt_wrapper
	},
	&in_chapol_init_wrapper
};

static void
out_chapol_init(br_sslrec_chapol_context *cc,
	br_chacha20_run ichacha, br_poly1305_run ipoly,
	const void *key, const void *iv)
{
	cc->vtable.out = &br_sslrec_out_chapol_vtable;
	gen_chapol_init(cc, ichacha, ipoly, key, iv);
}

static void
chapol_max_plaintext(const br_sslrec_chapol_context *cc,
	size_t *start, size_t *end)
{
	size_t len;

	(void)cc;
	len = *end - *start - 16;
	if (len > 16384) {
		len = 16384;
	}
	*end = *start + len;
}

static unsigned char *
chapol_encrypt(br_sslrec_chapol_context *cc,
	int record_type, unsigned version, void *data, size_t *data_len)
{
	unsigned char *buf;
	size_t len;

	buf = data;
	len = *data_len;
	gen_chapol_process(cc, record_type, version, buf, len, buf + len, 1);
	buf -= 5;
	buf[0] = (unsigned char)record_type;
	br_enc16be(buf + 1, version);
	br_enc16be(buf + 3, len + 16);
	*data_len = len + 21;
	return buf;
}

/* see bearssl_ssl.h */
static void
chapol_max_plaintext_wrapper(const br_sslrec_out_class *const * a0,
			size_t * a1, size_t * a2)
{
	chapol_max_plaintext((void *)a0, a1, a2);
}

static unsigned char *
chapol_encrypt_wrapper(const br_sslrec_out_class ** a0,
			int a1, unsigned a2, void * a3, size_t * a4)
{
	return chapol_encrypt((void *)a0, a1, a2, a3, a4);
}

static void
out_chapol_init_wrapper(const br_sslrec_out_chapol_class ** a0,
		br_chacha20_run a1, br_poly1305_run a2,
		const void * a3, const void * a4)
{
	out_chapol_init((void *)a0, a1, a2, a3, a4);
}

const br_sslrec_out_chapol_class br_sslrec_out_chapol_vtable = {
	{
		sizeof(br_sslrec_chapol_context),
		&chapol_max_plaintext_wrapper,
		&chapol_encrypt_wrapper
	},
	&out_chapol_init_wrapper
};
