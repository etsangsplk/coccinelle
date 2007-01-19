@@
identifier I;
expression E1, E2;
@@

struct i2c_client I {
- 	.name = E1,
+	.dev = { .name = E1 }
}

@@
struct i2c_client *x;
expression E;
@@

- x->data = E
+ i2c_set_clientdata(x,E)

@@
struct i2c_client *x;
expression E;
@@

(
- x->name
+ x->dev.name
|
- x->data
+ i2c_get_clientdata(x)
)

@@
struct i2c_client *x;
expression E1, E2, E3;
@@

  x = kmalloc(E1, E2)
  ...
  if (!x) { ... return ...; }
+ memset(x,0,E1);
  ... when != memcpy(x,E3,E1)