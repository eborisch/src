/*	$OpenBSD: parser.h,v 1.4 2019/10/31 12:51:43 florian Exp $	*/

/*
 * Copyright (c) 2004 Esben Norby <norby@openbsd.org>
 * Copyright (c) 2003, 2004 Henning Brauer <henning@openbsd.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

enum actions {
	NONE,
	LOG_DEBUG,
	LOG_VERBOSE,
	LOG_BRIEF,
	RELOAD,
	PORTAL,
	STATUS,
	STATUS_RECURSOR,
	STATUS_DHCP,
	STATUS_STATIC,
	STATUS_DOT,
	STATUS_ASR
};

struct parse_result {
	enum actions	action;
};

struct parse_result	*parse(int, char *[]);
