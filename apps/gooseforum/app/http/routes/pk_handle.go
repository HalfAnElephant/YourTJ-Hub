package routes

import (
	"net/http"

	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/http/controllers/pk"
	"github.com/gin-gonic/gin"
)

// pkJsonReq binds a JSON body and emits the PK envelope {code,msg,data}.
func pkJsonReq[T any](action func(pkcontroller.Request[T]) pkcontroller.Response) func(c *gin.Context) {
	return func(c *gin.Context) {
		var params T
		if err := c.ShouldBindJSON(&params); err != nil {
			c.JSON(http.StatusBadRequest, pkcontroller.BadRequest("参数错误"))
			return
		}
		resp := action(pkcontroller.Request[T]{Params: params, GinContext: c})
		c.JSON(resp.HTTPStatus(), resp)
	}
}

// pkQueryReq binds query parameters and emits the PK envelope.
func pkQueryReq[T any](action func(pkcontroller.Request[T]) pkcontroller.Response) func(c *gin.Context) {
	return func(c *gin.Context) {
		var params T
		if err := c.ShouldBindQuery(&params); err != nil {
			c.JSON(http.StatusBadRequest, pkcontroller.BadRequest("参数错误"))
			return
		}
		resp := action(pkcontroller.Request[T]{Params: params, GinContext: c})
		c.JSON(resp.HTTPStatus(), resp)
	}
}

// pkNoReq emits the PK envelope for handlers without request parameters.
func pkNoReq(action func(pkcontroller.Request[pkcontroller.Null]) pkcontroller.Response) func(c *gin.Context) {
	return func(c *gin.Context) {
		resp := action(pkcontroller.Request[pkcontroller.Null]{GinContext: c})
		c.JSON(resp.HTTPStatus(), resp)
	}
}

// pkAuthNoReq 包装登录态端点（issue #537）：填充 UserId（JWTAuthCheck 中间件
// 已写入 gin 上下文 "userId"），发出 PK 信封 {code,msg,data}。
func pkAuthNoReq(action func(pkcontroller.Request[pkcontroller.Null]) pkcontroller.Response) func(c *gin.Context) {
	return func(c *gin.Context) {
		resp := action(pkcontroller.Request[pkcontroller.Null]{UserId: c.GetUint64("userId"), GinContext: c})
		c.JSON(resp.HTTPStatus(), resp)
	}
}

// pkAuthJsonReq 绑定 JSON 请求体并填充 UserId，发出 PK 信封。
func pkAuthJsonReq[T any](action func(pkcontroller.Request[T]) pkcontroller.Response) func(c *gin.Context) {
	return func(c *gin.Context) {
		var params T
		if err := c.ShouldBindJSON(&params); err != nil {
			c.JSON(http.StatusBadRequest, pkcontroller.BadRequest("参数错误"))
			return
		}
		resp := action(pkcontroller.Request[T]{Params: params, UserId: c.GetUint64("userId"), GinContext: c})
		c.JSON(resp.HTTPStatus(), resp)
	}
}
