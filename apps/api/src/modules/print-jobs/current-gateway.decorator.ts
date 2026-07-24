import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthenticatedGateway } from './gateway-auth.guard';

export const CurrentGateway = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthenticatedGateway =>
    ctx.switchToHttp().getRequest().gateway,
);
