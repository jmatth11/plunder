#include <stdlib.h>
#include <unistd.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <signal.h>

atomic_bool signal_received = ATOMIC_VAR_INIT(false);

void signal_handler(int signum) {
  atomic_store(&signal_received, true);
}

int main (void) {
  signal(SIGINT, signal_handler);
  signal(SIGTERM, signal_handler);
  char *name = malloc(sizeof(char) * 11);
  name[0] = 't';
  name[1] = 'e';
  name[2] = 's';
  name[3] = 't';
  name[4] = ' ';
  name[5] = 's';
  name[6] = 't';
  name[7] = 'r';
  name[8] = 'i';
  name[9] = 'n';
  name[10] = 'g';
  while (!atomic_load(&signal_received)) {
    sleep(1);
  }
  free(name);
  return 0;
}
