#include <stdio.h>
#include <stdlib.h>

int main (void) {
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
  (void)getchar();
  free(name);
  return 0;
}
