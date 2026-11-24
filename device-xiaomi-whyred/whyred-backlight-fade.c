// SPDX-License-Identifier: GPL-2.0-only
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static int read_int(const char *path, int def)
{
	char buf[32];
	int fd, n, val;

	fd = open(path, O_RDONLY);
	if (fd < 0)
		return def;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return def;
	buf[n] = '\0';
	val = atoi(buf);
	return val;
}

static int write_int(const char *path, int val)
{
	char buf[32];
	int fd, n, len, ret;

	len = snprintf(buf, sizeof(buf), "%d\n", val);
	fd = open(path, O_WRONLY);
	if (fd < 0)
		return -1;
	n = write(fd, buf, len);
	close(fd);
	return n == len ? 0 : -1;
}

int main(int argc, char **argv)
{
	const char *brightness = "/sys/class/backlight/backlight/brightness";
	const char *actual = "/sys/class/backlight/backlight/actual_brightness";
	const char *maxpath = "/sys/class/backlight/backlight/max_brightness";
	int target, duration, current, max, steps, i;

	if (argc < 2)
		return 2;

	target = atoi(argv[1]);
	duration = argc > 2 ? atoi(argv[2]) : 800;
	if (duration < 10)
		duration = 10;

	max = read_int(maxpath, 4095);
	if (max <= 0)
		max = 4095;
	if (target < 0)
		target = 0;
	if (target > max)
		target = max;

	current = read_int(actual, target);
	if (current < 0)
		current = 0;
	if (current > max)
		current = max;
	if (current == target)
		return 0;

	steps = duration / 10;
	if (steps < 1)
		steps = 1;
	if (steps > 1000)
		steps = 1000;

	for (i = 1; i <= steps; i++) {
		int value = current + (target - current) * i / steps;
		struct timespec ts = { .tv_sec = 0, .tv_nsec = 10000000 };

		write_int(brightness, value);
		nanosleep(&ts, NULL);
	}
	write_int(brightness, target);
	return 0;
}
