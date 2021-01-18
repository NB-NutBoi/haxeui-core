package haxe.ui.backend;

import haxe.ui.components.Button;
import haxe.ui.containers.Box;
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.core.Component;
import haxe.ui.core.Screen;
import haxe.ui.events.MouseEvent;
import haxe.ui.styles.Style;

@:dox(hide) @:noCompletion
class DialogBase extends Box {
    public var modal:Bool = true;
    public var buttons:DialogButton = null;
    public var centerDialog:Bool = true;
    public var button:DialogButton = null;

    private var _overlay:Component;

    public var dialogContainer:haxe.ui.containers.VBox;
    public var dialogTitle:haxe.ui.containers.HBox;
    public var dialogTitleLabel:haxe.ui.components.Label;
    public var dialogCloseButton:haxe.ui.components.Image;
    public var dialogContent:haxe.ui.containers.VBox;
    public var dialogFooterContainer:haxe.ui.containers.Box;
    public var dialogFooter:haxe.ui.containers.HBox;

    public function new() {
        super();

        dialogContainer = new haxe.ui.containers.VBox();
        dialogContainer.id = "dialog-container";
        dialogContainer.styleNames = "dialog-container";
        addComponent(dialogContainer);

        dialogTitle = new haxe.ui.containers.HBox();
        dialogTitle.id = "dialog-title";
        dialogTitle.styleNames = "dialog-title";
        dragInitiator = dialogTitle;
        dialogContainer.addComponent(dialogTitle);

        dialogTitleLabel = new haxe.ui.components.Label();
        dialogTitleLabel.id = "dialog-title-label";
        dialogTitleLabel.styleNames = "dialog-title-label";
        dialogTitleLabel.text = "HaxeUI";
        dialogTitle.addComponent(dialogTitleLabel);

        dialogCloseButton = new haxe.ui.components.Image();
        dialogCloseButton.id = "dialog-close-button";
        dialogCloseButton.styleNames = "dialog-close-button";
        dialogTitle.addComponent(dialogCloseButton);

        dialogContent = new haxe.ui.containers.VBox();
        dialogContent.id = "dialog-content";
        dialogContent.styleNames = "dialog-content";
        dialogContainer.addComponent(dialogContent);

        dialogFooterContainer = new haxe.ui.containers.Box();
        dialogFooterContainer.id = "dialog-footer-container";
        dialogFooterContainer.styleNames = "dialog-footer-container";
        dialogContainer.addComponent(dialogFooterContainer);

        dialogFooter = new haxe.ui.containers.HBox();
        dialogFooter.id = "dialog-footer";
        dialogFooter.styleNames = "dialog-footer";
        dialogFooterContainer.addComponent(dialogFooter);

        dialogFooterContainer.hide();
        dialogCloseButton.onClick = function(e) {
            hideDialog(DialogButton.CANCEL);
        }
    }

    private override function applyStyle(style:Style) {
        super.applyStyle(style);
        if (this.autoWidth == false) {
            dialogFooterContainer.percentWidth = 100;
        }
    }
    
    private var _dialogParent:Component = null;
    public var dialogParent(get, set):Component;
    private function get_dialogParent():Component {
        return _dialogParent;
    }
    private function set_dialogParent(value:Component):Component {
        _dialogParent = value;
        return value;
    }

    public function showDialog(modal:Bool = true) {
        this.modal = modal;
        show();
    }

    public override function show() {
        var dp = dialogParent;
        if (modal) {
            _overlay = new Component();
            _overlay.id = "modal-background";
            _overlay.addClass("modal-background");
            _overlay.percentWidth = _overlay.percentHeight = 100;
            if (dp != null) {
                dp.addComponent(_overlay);
            } else {
                Screen.instance.addComponent(_overlay);
            }
        }
        createButtons();

        if (dp != null) {
            dp.addComponent(this);
        } else {
            Screen.instance.addComponent(this);
        }
        this.syncComponentValidation();
        if (autoHeight == false) {
            dialogContainer.percentHeight = 100;
            dialogContent.percentHeight = 100;
        }
        if (centerDialog) {
            centerDialogComponent(cast(this, Dialog));
        }
    }

    private var _buttonsCreated:Bool = false;
    private function createButtons() {
        if (_buttonsCreated == true) {
            return;
        }
        if (buttons != null) {
            for (button in buttons.toArray()) {
                var buttonComponent = new Button();
                buttonComponent.text = button.toString();
                buttonComponent.userData = button;
                buttonComponent.registerEvent(MouseEvent.CLICK, onFooterButtonClick);
                addFooterComponent(buttonComponent);
            }
            _buttonsCreated = true;
        }
    }

    public var closable(get, set):Bool;
    private function get_closable():Bool {
        return !dialogCloseButton.hidden;
    }
    private function set_closable(value:Bool):Bool {
        if (value == true) {
            dialogCloseButton.show();
        } else {
            dialogCloseButton.hide();
        }
        return value;
    }

    private function validateDialog(button:DialogButton, fn:Bool->Void) {
        fn(true);
    }

    public override function hide() {
        validateDialog(this.button, function(result) {
            if (result == true) {
                var dp = dialogParent;
                if (modal && _overlay != null) {
                    if (dp != null) {
                        dp.removeComponent(_overlay);
                    } else {
                        Screen.instance.removeComponent(_overlay);
                    }
                }
                if (dp != null) {
                    dp.removeComponent(this, false);
                } else {
                    Screen.instance.removeComponent(this);
                }

                var event = new DialogEvent(DialogEvent.DIALOG_CLOSED);
                event.button = this.button;
                dispatch(event);
            }
        });
    }

    public function hideDialog(button:DialogButton) {
        this.button = button;
        hide();
    }

    public var title(get, set):String;
    private function get_title():String {
        return dialogTitleLabel.text;
    }
    private function set_title(value:String):String {
        dialogTitleLabel.text = value;
        return value;
    }

    public override function addComponent(child:Component):Component {
        if (child.hasClass("dialog-container")) {
            return super.addComponent(child);
        }
        return dialogContent.addComponent(child);
    }

    public override function validateComponentLayout():Bool {
        var b = super.validateComponentLayout();
        dialogTitle.width = this.layout.innerWidth;
        if (autoWidth == false) {
            dialogContent.width = this.layout.innerWidth;
        } else if (dialogFooterContainer.width < this.layout.innerWidth) {
            dialogFooterContainer.width = this.layout.innerWidth;
        }
        return b;
    }

    public function addFooterComponent(c:Component) {
        dialogFooterContainer.show();
        dialogFooter.addComponent(c);
    }

    public function centerDialogComponent(dialog:Dialog) {
        dialog.syncComponentValidation();
        var dp = dialogParent;
        if (dp != null) {
            dp.syncComponentValidation();
            var x = (dp.width / 2) - (dialog.componentWidth / 2);
            var y = (dp.height / 2) - (dialog.componentHeight / 2);
            dialog.moveComponent(x, y);
        } else {
            var x = (Screen.instance.width / 2) - (dialog.componentWidth / 2);
            var y = (Screen.instance.height / 2) - (dialog.componentHeight / 2);
            dialog.moveComponent(x, y);
        }
    }

    private function onFooterButtonClick(event:MouseEvent) {
        hideDialog(event.target.userData);
    }
}
