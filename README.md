# LibVM
Virtual machine for OpenOS

Виртуальная машина для операционной системы OpenOS, для мода opencomputers в игре minecraft.

## Задачи, решения которых я собираюсь достигнуть в процессе разработки
* Возможность виртуального тестирования биоса, что значительно упростит процесс разработки программ для EEPROM
* Полноценный запуск любых операционных систем внутри OpenOS, включая саму OpenOS, а так же MineOS
* Следуя из последнего пункта, возможность использования несовместимых с OpenOS программ
* Безопасное выполнение программ, которые могут навредить компьютеру
* Весело проведённое за разработкой виртуальной машины время :)

> На данный момент проект находится в процессе активной разработки, **недоделан**, имеет много багов и недочётов. Поэтому документации и инструкции ~~пока-что~~ нет.

## Демонстрация
Уже сейчас мне удалось запустить MineOS, и вот как это выглядит:
![image](https://user-images.githubusercontent.com/33802666/190020661-519f5d3f-d4b6-4e6c-9e30-6c3513b8ddcb.png)

## Установка
Если ~~на кой-то хуй~~ вам понадобится установить это, вот команды:

через pastebin:
```
  pastebin run SAX9kpVE
```

или напрямую:
```
  wget -f https://raw.githubusercontent.com/Smok1e/oc-openos-libvm/main/installer/get-libvm.lua /tmp/get-libvm.lua && /tmp/get-libvm.lua
```
